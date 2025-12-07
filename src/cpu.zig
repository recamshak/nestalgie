const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const StatusFlags = packed struct {
    carry: u1 = 0,
    zero: u1 = 0,
    interruptDisable: u1 = 0,
    decimal: u1 = 0,
    b: u1 = 0,
    _pad: u1 = 1,
    overflow: u1 = 0,
    negative: u1 = 0,
};

pub fn Nes6502(
    comptime read_u8: *const fn (address: u16) callconv(.@"inline") u8,
    comptime read_u16: *const fn (address: u16) callconv(.@"inline") u16,
    comptime write_u8: *const fn (address: u16, value: u8) callconv(.@"inline") void,
) type {
    return struct {
        const Self = @This();
        const Operation = struct {
            *const fn (self: *Self, op_code: u8) u8,
            ?*const fn (self: *Self) Operand,
            u8,
        };
        const Operand = struct {
            value: u8,
            address: ?u16 = null,
            page_crossed: bool = false,
        };

        pc: u16 = 0xFFFC,
        a: u8 = 0,
        x: u8 = 0,
        y: u8 = 0,
        s: u8 = 0xFD,
        status: StatusFlags = StatusFlags{},

        irq: u1 = 0,
        nmi: u1 = 0,

        const illegal = Operation{ .execute = op_illegal, .cycles = 1 };
        const nop = Operation{ op_nop, null, 2 };
        const not_supported = Operation{ .execute = op_not_supported, .cycles = 1 };

        var op_table: [256]Operation = [_]Operation{.{ op_adc, @"absolute mode", 4 }} ** 256;
        pub fn init() void {
            // ADC - Add with Carry
            op_table[0x69] = Operation{ op_adc, @"#immediate mode", 2 };
            op_table[0x65] = Operation{ op_adc, @"zero page mode", 3 };
            op_table[0x75] = Operation{ op_adc, @"zero page,x mode", 4 };
            op_table[0x6d] = Operation{ op_adc, @"absolute mode", 4 };
            op_table[0x7d] = Operation{ op_adc, @"absolute,x mode", 4 };
            op_table[0x79] = Operation{ op_adc, @"absolute,y mode", 4 };
            op_table[0x61] = Operation{ op_adc, @"(indirect,x) mode", 6 };
            op_table[0x71] = Operation{ op_adc, @"(indirect),y mode", 5 };

            // AND - Logical AND
            op_table[0x29] = Operation{ op_and, @"#immediate mode", 2 };
            op_table[0x25] = Operation{ op_and, @"zero page mode", 3 };
            op_table[0x35] = Operation{ op_and, @"zero page,x mode", 4 };
            op_table[0x2d] = Operation{ op_and, @"absolute mode", 4 };
            op_table[0x3d] = Operation{ op_and, @"absolute,x mode", 4 };
            op_table[0x39] = Operation{ op_and, @"absolute,y mode", 4 };
            op_table[0x21] = Operation{ op_and, @"(indirect,x) mode", 6 };
            op_table[0x31] = Operation{ op_and, @"(indirect),y mode", 5 };

            // ASL - Arithmetic Shift Left
            op_table[0x0a] = Operation{ op_asl, @"accumulator mode", 2 };
            op_table[0x06] = Operation{ op_asl, @"zero page mode", 5 };
            op_table[0x16] = Operation{ op_asl, @"zero page,x mode", 6 };
            op_table[0x0e] = Operation{ op_asl, @"absolute mode", 6 };
            op_table[0x1e] = Operation{ op_asl, @"absolute,x mode", 7 };

            // BCC - Branch if Carry Clear
            op_table[0x90] = Operation{ op_bcc, null, 0 };

            // BCS - Branch if Carry Set
            op_table[0xb0] = Operation{ op_bcs, null, 0 };

            // BEQ - Branch if Equal (Zero Set)
            op_table[0xf0] = Operation{ op_beq, null, 0 };

            // BIT - Bit Test
            op_table[0x24] = Operation{ op_bit, @"zero page mode", 3 };
            op_table[0x2c] = Operation{ op_bit, @"absolute mode", 4 };

            // BMI - Branch if Minus
            op_table[0x30] = Operation{ op_bmi, null, 0 };

            // BNE - Branch if Not Equal
            op_table[0xd0] = Operation{ op_bne, null, 0 };

            // BPL - Branch if Plus
            op_table[0x10] = Operation{ op_bpl, null, 0 };

            // BRK - Break
            op_table[0x00] = Operation{ op_brk, null, 7 };

            // BVC - Branch if Overflow Clear
            op_table[0x50] = Operation{ op_bvc, null, 0 };

            // BVS - Branch if Overflow Set
            op_table[0x70] = Operation{ op_bvs, null, 0 };

            // CLC - Clear Carry Flag
            op_table[0x18] = Operation{ op_clc, null, 2 };

            // CLD - Clear Decimal Mode
            op_table[0xd8] = Operation{ op_cld, null, 2 };

            // CLI - Clear Interrupt Disable
            op_table[0x58] = Operation{ op_cli, null, 2 };

            // CLV - Clear Overflow Flag
            op_table[0xb8] = Operation{ op_clv, null, 2 };

            // CMP - Compare Accumulator
            op_table[0xc9] = Operation{ op_cmp, @"#immediate mode", 2 };
            op_table[0xc5] = Operation{ op_cmp, @"zero page mode", 3 };
            op_table[0xd5] = Operation{ op_cmp, @"zero page,x mode", 4 };
            op_table[0xcd] = Operation{ op_cmp, @"absolute mode", 4 };
            op_table[0xdd] = Operation{ op_cmp, @"absolute,x mode", 4 };
            op_table[0xd9] = Operation{ op_cmp, @"absolute,y mode", 4 };
            op_table[0xc1] = Operation{ op_cmp, @"(indirect,x) mode", 6 };
            op_table[0xd1] = Operation{ op_cmp, @"(indirect),y mode", 5 };

            // CPX - Compare X Register
            op_table[0xe0] = Operation{ op_cpx, @"#immediate mode", 2 };
            op_table[0xe4] = Operation{ op_cpx, @"zero page mode", 3 };
            op_table[0xec] = Operation{ op_cpx, @"absolute mode", 4 };

            // CPY - Compare Y Register
            op_table[0xc0] = Operation{ op_cpy, @"#immediate mode", 2 };
            op_table[0xc4] = Operation{ op_cpy, @"zero page mode", 3 };
            op_table[0xcc] = Operation{ op_cpy, @"absolute mode", 4 };

            // DEC - Decrement Memory
            op_table[0xc6] = Operation{ op_dec, @"zero page mode", 5 };
            op_table[0xd6] = Operation{ op_dec, @"zero page,x mode", 6 };
            op_table[0xce] = Operation{ op_dec, @"absolute mode", 6 };
            op_table[0xde] = Operation{ op_dec, @"absolute,x mode", 7 };

            // DEX - Decrement X Register
            op_table[0xca] = Operation{ op_dex, null, 2 };

            // DEY - Decrement Y Register
            op_table[0x88] = Operation{ op_dey, null, 2 };

            // EOR - Exclusive OR
            op_table[0x49] = Operation{ op_eor, @"#immediate mode", 2 };
            op_table[0x45] = Operation{ op_eor, @"zero page mode", 3 };
            op_table[0x55] = Operation{ op_eor, @"zero page,x mode", 4 };
            op_table[0x4d] = Operation{ op_eor, @"absolute mode", 4 };
            op_table[0x5d] = Operation{ op_eor, @"absolute,x mode", 4 };
            op_table[0x59] = Operation{ op_eor, @"absolute,y mode", 4 };
            op_table[0x41] = Operation{ op_eor, @"(indirect,x) mode", 6 };
            op_table[0x51] = Operation{ op_eor, @"(indirect),y mode", 5 };

            // INC - Increment Memory
            op_table[0xe6] = Operation{ op_inc, @"zero page mode", 5 };
            op_table[0xf6] = Operation{ op_inc, @"zero page,x mode", 6 };
            op_table[0xee] = Operation{ op_inc, @"absolute mode", 6 };
            op_table[0xfe] = Operation{ op_inc, @"absolute,x mode", 7 };

            // INX - Increment X Register
            op_table[0xe8] = Operation{ op_inx, null, 2 };

            // INY - Increment Y Register
            op_table[0xc8] = Operation{ op_iny, null, 2 };

            // JMP - Jump
            op_table[0x4c] = Operation{ op_jmp, null, 3 };
            op_table[0x6c] = Operation{ op_jmp_indirect, null, 5 };

            // JSR - Jump to Subroutine
            op_table[0x20] = Operation{ op_jsr, @"absolute mode", 6 };

            // LDA - Load Accumulator
            op_table[0xa9] = Operation{ op_lda, @"#immediate mode", 2 };
            op_table[0xa5] = Operation{ op_lda, @"zero page mode", 3 };
            op_table[0xb5] = Operation{ op_lda, @"zero page,x mode", 4 };
            op_table[0xad] = Operation{ op_lda, @"absolute mode", 4 };
            op_table[0xbd] = Operation{ op_lda, @"absolute,x mode", 4 };
            op_table[0xb9] = Operation{ op_lda, @"absolute,y mode", 4 };
            op_table[0xa1] = Operation{ op_lda, @"(indirect,x) mode", 6 };
            op_table[0xb1] = Operation{ op_lda, @"(indirect),y mode", 5 };

            // LDX - Load X Register
            op_table[0xa2] = Operation{ op_ldx, @"#immediate mode", 2 };
            op_table[0xa6] = Operation{ op_ldx, @"zero page mode", 3 };
            op_table[0xb6] = Operation{ op_ldx, @"zero page,y mode", 4 };
            op_table[0xae] = Operation{ op_ldx, @"absolute mode", 4 };
            op_table[0xbe] = Operation{ op_ldx, @"absolute,y mode", 4 };

            // LDY - Load Y Register
            op_table[0xa0] = Operation{ op_ldy, @"#immediate mode", 2 };
            op_table[0xa4] = Operation{ op_ldy, @"zero page mode", 3 };
            op_table[0xb4] = Operation{ op_ldy, @"zero page,x mode", 4 };
            op_table[0xac] = Operation{ op_ldy, @"absolute mode", 4 };
            op_table[0xbc] = Operation{ op_ldy, @"absolute,x mode", 4 };

            // LSR - Logical Shift Right
            op_table[0x4a] = Operation{ op_lsr, @"accumulator mode", 2 };
            op_table[0x46] = Operation{ op_lsr, @"zero page mode", 5 };
            op_table[0x56] = Operation{ op_lsr, @"zero page,x mode", 6 };
            op_table[0x4e] = Operation{ op_lsr, @"absolute mode", 6 };
            op_table[0x5e] = Operation{ op_lsr, @"absolute,x mode", 7 };

            // NOP - No Operation
            op_table[0xea] = nop;

            // ORA - Logical Inclusive OR
            op_table[0x09] = Operation{ op_ora, @"#immediate mode", 2 };
            op_table[0x05] = Operation{ op_ora, @"zero page mode", 3 };
            op_table[0x15] = Operation{ op_ora, @"zero page,x mode", 4 };
            op_table[0x0d] = Operation{ op_ora, @"absolute mode", 4 };
            op_table[0x1d] = Operation{ op_ora, @"absolute,x mode", 4 };
            op_table[0x19] = Operation{ op_ora, @"absolute,y mode", 4 };
            op_table[0x01] = Operation{ op_ora, @"(indirect,x) mode", 6 };
            op_table[0x11] = Operation{ op_ora, @"(indirect),y mode", 5 };

            // PHA - Push Accumulator
            op_table[0x48] = Operation{ op_pha, null, 3 };

            // PHP - Push Processor Status
            op_table[0x08] = Operation{ op_php, null, 3 };

            // PLA - Pull Accumulator
            op_table[0x68] = Operation{ op_pla, null, 4 };

            // PLP - Pull Processor Status
            op_table[0x28] = Operation{ op_plp, null, 4 };

            // ROL - Rotate Left
            op_table[0x2a] = Operation{ op_rol, @"accumulator mode", 2 };
            op_table[0x26] = Operation{ op_rol, @"zero page mode", 5 };
            op_table[0x36] = Operation{ op_rol, @"zero page,x mode", 6 };
            op_table[0x2e] = Operation{ op_rol, @"absolute mode", 6 };
            op_table[0x3e] = Operation{ op_rol, @"absolute,x mode", 7 };

            // ROR - Rotate Right
            op_table[0x6a] = Operation{ op_ror, @"accumulator mode", 2 };
            op_table[0x66] = Operation{ op_ror, @"zero page mode", 5 };
            op_table[0x76] = Operation{ op_ror, @"zero page,x mode", 6 };
            op_table[0x6e] = Operation{ op_ror, @"absolute mode", 6 };
            op_table[0x7e] = Operation{ op_ror, @"absolute,x mode", 7 };

            // RTI - Return from Interrupt
            op_table[0x40] = Operation{ op_rti, null, 6 };

            // RTS - Return from Subroutine
            op_table[0x60] = Operation{ op_rts, null, 6 };

            // SBC - Subtract with Carry
            op_table[0xe9] = Operation{ op_sbc, @"#immediate mode", 2 };
            op_table[0xe5] = Operation{ op_sbc, @"zero page mode", 3 };
            op_table[0xf5] = Operation{ op_sbc, @"zero page,x mode", 4 };
            op_table[0xed] = Operation{ op_sbc, @"absolute mode", 4 };
            op_table[0xfd] = Operation{ op_sbc, @"absolute,x mode", 4 };
            op_table[0xf9] = Operation{ op_sbc, @"absolute,y mode", 4 };
            op_table[0xe1] = Operation{ op_sbc, @"(indirect,x) mode", 6 };
            op_table[0xf1] = Operation{ op_sbc, @"(indirect),y mode", 5 };

            // SEC - Set Carry Flag
            op_table[0x38] = Operation{ op_sec, null, 2 };

            // SED - Set Decimal Flag
            op_table[0xf8] = Operation{ op_sed, null, 2 };

            // SEI - Set Interrupt Disable
            op_table[0x78] = Operation{ op_sei, null, 2 };

            // STA - Store Accumulator
            op_table[0x85] = Operation{ op_sta, @"zero page mode: write", 3 };
            op_table[0x95] = Operation{ op_sta, @"zero page,x mode: write", 4 };
            op_table[0x8d] = Operation{ op_sta, @"absolute mode: write", 4 };
            op_table[0x9d] = Operation{ op_sta, @"absolute,x mode: write", 5 };
            op_table[0x99] = Operation{ op_sta, @"absolute,y mode: write", 5 };
            op_table[0x81] = Operation{ op_sta, @"(indirect,x) mode: write", 6 };
            op_table[0x91] = Operation{ op_sta, @"(indirect),y mode: write", 6 };

            // STX - Store X Register
            op_table[0x86] = Operation{ op_stx, @"zero page mode: write", 3 };
            op_table[0x96] = Operation{ op_stx, @"zero page,y mode: write", 4 };
            op_table[0x8e] = Operation{ op_stx, @"absolute mode: write", 4 };

            // STY - Store Y Register
            op_table[0x84] = Operation{ op_sty, @"zero page mode: write", 3 };
            op_table[0x94] = Operation{ op_sty, @"zero page,x mode: write", 4 };
            op_table[0x8c] = Operation{ op_sty, @"absolute mode: write", 4 };

            // TAX - Transfer Accumulator to X
            op_table[0xaa] = Operation{ op_tax, null, 2 };

            // TAY - Transfer Accumulator to Y
            op_table[0xa8] = Operation{ op_tay, null, 2 };

            // TSX - Transfer Stack Pointer to X
            op_table[0xba] = Operation{ op_tsx, null, 2 };

            // TXA - Transfer X to Accumulator
            op_table[0x8a] = Operation{ op_txa, null, 2 };

            // TXS - Transfer X to Stack Pointer
            op_table[0x9a] = Operation{ op_txs, null, 2 };

            // TYA - Transfer Y to Accumulator
            op_table[0x98] = Operation{ op_tya, null, 2 };
        }

        inline fn read_next_u8(self: *Self) u8 {
            defer self.pc +%= 1;
            return read_u8(self.pc);
        }

        inline fn read_next_u16(self: *Self) u16 {
            defer self.pc +%= 2;
            return read_u16(self.pc);
        }

        pub fn execute_next_op(self: *Self) u8 {
            const op_code = self.read_next_u8();
            const op = op_table[op_code];
            return self.execute(op, op_code);
        }

        fn op_illegal(_: *Self) void {
            unreachable;
        }
        fn op_nop(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            return cycles(op_table[op_code]);
        }
        fn op_not_supported(_: *Self) void {
            unreachable;
        }

        fn op_adc(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            var result, const carry1 = @addWithOverflow(self.a, operand.value);
            result, const carry2 = @addWithOverflow(result, self.status.carry);

            self.status.carry = carry1 | carry2;
            self.status.zero = @bitCast(result == 0);
            self.status.overflow = @bitCast((result ^ self.a) & (result ^ operand.value) & 0x80 != 0);
            self.status.negative = @bitCast(result & 0x80 != 0);
            self.a = result;

            return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
        }

        fn op_and(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            const result = self.a & operand.value;
            self.status.zero = @bitCast(result == 0);
            self.status.negative = @bitCast(result & 0x80 != 0);
            self.a = result;
            return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
        }

        fn op_asl(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            const result, const carry = @shlWithOverflow(operand.value, 1);
            if (operand.address) |address| {
                write_u8(address, operand.value);
                write_u8(address, result);
            } else {
                self.a = result;
            }
            self.status.zero = @bitCast(result == 0);
            self.status.carry = carry;
            self.status.negative = @bitCast(result & 0x80 != 0);
            return cycles(op_table[op_code]);
        }

        fn relative_branch(self: *Self, jump: bool) u8 {
            const operand = self.read_next_u8();
            if (jump) {
                const new_pc: u16 = @bitCast(@as(i16, @bitCast(self.pc)) +% @as(i8, @bitCast(operand)));
                const page_crossed = (self.pc & 0xff00) != (new_pc & 0xff00);

                if (builtin.is_test) {
                    _ = read_u8(self.pc);
                    if (page_crossed) {
                        const new_pc_without_carry: u16 = (self.pc & 0xff00) + @as(u16, @bitCast(@as(i16, @bitCast(self.pc)) +% @as(i8, @bitCast(operand)) & 0x00ff));
                        _ = read_u8(new_pc_without_carry);
                    }
                }

                self.pc = new_pc;
                return @as(u8, 3) + @as(u1, @bitCast(page_crossed));
            }
            return 2;
        }

        fn op_bcc(self: *Self, _: u8) u8 {
            return self.relative_branch(self.status.carry == 0);
        }

        fn op_bcs(self: *Self, _: u8) u8 {
            return self.relative_branch(self.status.carry == 1);
        }

        fn op_beq(self: *Self, _: u8) u8 {
            return self.relative_branch(self.status.zero == 1);
        }

        fn op_bmi(self: *Self, _: u8) u8 {
            return self.relative_branch(self.status.negative == 1);
        }

        fn op_bne(self: *Self, _: u8) u8 {
            return self.relative_branch(self.status.zero == 0);
        }

        fn op_bpl(self: *Self, _: u8) u8 {
            return self.relative_branch(self.status.negative == 0);
        }

        fn op_bvc(self: *Self, _: u8) u8 {
            return self.relative_branch(self.status.overflow == 0);
        }

        fn op_bvs(self: *Self, _: u8) u8 {
            return self.relative_branch(self.status.overflow == 1);
        }

        fn op_brk(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.push_u16(self.pc +% 1);
            self.push_u8(@as(u8, @bitCast(self.status)) | 0x30);
            self.pc = read_u16(0xfffe);
            self.status.interruptDisable = 1;
            return cycles(op_table[op_code]);
        }

        fn op_clc(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.status.carry = 0;
            return cycles(op_table[op_code]);
        }

        fn op_cld(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.status.decimal = 0;
            return cycles(op_table[op_code]);
        }

        fn op_cli(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.status.interruptDisable = 0;
            return cycles(op_table[op_code]);
        }

        fn op_clv(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.status.overflow = 0;
            return cycles(op_table[op_code]);
        }

        fn op_cmp(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            self.status.carry = @bitCast(self.a >= operand.value);
            self.status.zero = @bitCast(self.a == operand.value);
            self.status.negative = @bitCast((self.a -% operand.value) & 0x80 != 0);
            return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
        }

        fn op_cpx(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]).value;
            self.status.carry = @bitCast(self.x >= operand);
            self.status.zero = @bitCast(self.x == operand);
            self.status.negative = @bitCast((self.x -% operand) & 0x80 != 0);
            return cycles(op_table[op_code]);
        }

        fn op_cpy(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]).value;
            self.status.carry = @bitCast(self.y >= operand);
            self.status.zero = @bitCast(self.y == operand);
            self.status.negative = @bitCast((self.y -% operand) & 0x80 != 0);
            return cycles(op_table[op_code]);
        }

        fn op_dec(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            const result = operand.value -% 1;
            write_u8(operand.address.?, operand.value);
            write_u8(operand.address.?, result);
            self.status.zero = @bitCast(result == 0);
            self.status.negative = @bitCast(result & 0x80 != 0);
            return cycles(op_table[op_code]);
        }

        fn op_inc(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            const result = operand.value +% 1;
            write_u8(operand.address.?, operand.value);
            write_u8(operand.address.?, result);
            self.status.zero = @bitCast(result == 0);
            self.status.negative = @bitCast(result & 0x80 != 0);
            return cycles(op_table[op_code]);
        }

        fn op_dex(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.x = self.x -% 1;
            self.status.zero = @bitCast(self.x == 0);
            self.status.negative = @bitCast(self.x & 0x80 != 0);
            return cycles(op_table[op_code]);
        }

        fn op_dey(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.y = self.y -% 1;
            self.status.zero = @bitCast(self.y == 0);
            self.status.negative = @bitCast(self.y & 0x80 != 0);
            return cycles(op_table[op_code]);
        }

        fn op_inx(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.x = self.x +% 1;
            self.status.zero = @bitCast(self.x == 0);
            self.status.negative = @bitCast(self.x & 0x80 != 0);
            return cycles(op_table[op_code]);
        }

        fn op_iny(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.y = self.y +% 1;
            self.status.zero = @bitCast(self.y == 0);
            self.status.negative = @bitCast(self.y & 0x80 != 0);
            return cycles(op_table[op_code]);
        }

        fn op_eor(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            self.a = self.a ^ operand.value;
            self.status.zero = @bitCast(self.a == 0);
            self.status.negative = @bitCast(self.a & 0x80 != 0);
            return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
        }

        fn op_ora(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            self.a = self.a | operand.value;
            self.status.zero = @bitCast(self.a == 0);
            self.status.negative = @bitCast(self.a & 0x80 != 0);
            return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
        }

        fn op_jmp(self: *Self, op_code: u8) u8 {
            const address = self.read_next_u16();
            self.pc = address;
            return cycles(op_table[op_code]);
        }

        fn op_jmp_indirect(self: *Self, op_code: u8) u8 {
            const ptr = self.read_next_u16();
            if (ptr & 0xff == 0xff) {
                self.pc = @as(u16, read_u8(ptr)) | (@as(u16, read_u8(ptr & 0xff00)) << 8);
            } else {
                self.pc = read_u16(ptr);
            }
            return cycles(op_table[op_code]);
        }

        fn op_jsr(self: *Self, op_code: u8) u8 {
            const address_lo = @as(u16, self.read_next_u8());
            _ = self.read_stack_u8();
            self.push_u16(self.pc);
            const address_hi = @as(u16, self.read_next_u8());
            self.pc = (address_hi << 8) | address_lo;
            return cycles(op_table[op_code]);
        }

        fn op_lda(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            self.a = operand.value;
            self.status.zero = @bitCast(self.a == 0);
            self.status.negative = @bitCast(self.a & 0x80 != 0);
            return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
        }

        fn op_ldx(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            self.x = operand.value;
            self.status.zero = @bitCast(self.x == 0);
            self.status.negative = @bitCast(self.x & 0x80 != 0);
            return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
        }

        fn op_ldy(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            self.y = operand.value;
            self.status.zero = @bitCast(self.y == 0);
            self.status.negative = @bitCast(self.y & 0x80 != 0);
            return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
        }

        fn op_lsr(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            const result = operand.value >> 1;
            if (operand.address) |address| {
                write_u8(address, operand.value);
                write_u8(address, result);
            } else {
                self.a = result;
            }

            self.status.carry = @bitCast(operand.value & 0x01 != 0);
            self.status.zero = @bitCast(result == 0);
            self.status.negative = 0;
            return cycles(op_table[op_code]);
        }

        fn op_bit(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]).value;
            const result = self.a & operand;
            self.status.zero = @bitCast(result == 0);
            self.status.overflow = @bitCast(operand & 0x40 != 0);
            self.status.negative = @bitCast(operand & 0x80 != 0);

            return cycles(op_table[op_code]);
        }

        fn op_pha(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.push_u8(self.a);
            return cycles(op_table[op_code]);
        }
        fn op_php(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.push_u8(@as(u8, @bitCast(self.status)) | 0x30);
            return cycles(op_table[op_code]);
        }
        fn op_pla(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.a = self.pull_u8();
            self.status.zero = @bitCast(self.a == 0);
            self.status.negative = @bitCast(self.a & 0x80 != 0);
            return cycles(op_table[op_code]);
        }
        fn op_plp(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            const b = self.status.b;
            self.status = @bitCast(self.pull_u8() | 0x20);
            self.status.b = b;
            return cycles(op_table[op_code]);
        }
        fn op_rol(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            const result = operand.value << 1 | @as(u8, self.status.carry);
            if (operand.address) |address| {
                write_u8(address, operand.value);
                write_u8(address, result);
            } else {
                self.a = result;
            }
            self.status.carry = @bitCast(operand.value & 0x80 != 0);
            self.status.zero = @bitCast(result == 0);
            self.status.negative = @bitCast(result & 0x80 != 0);
            return cycles(op_table[op_code]);
        }
        fn op_ror(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            const result = operand.value >> 1 | (@as(u8, self.status.carry) << 7);
            if (operand.address) |address| {
                write_u8(address, operand.value);
                write_u8(address, result);
            } else {
                self.a = result;
            }
            self.status.carry = @bitCast(operand.value & 0x01 != 0);
            self.status.zero = @bitCast(result == 0);
            self.status.negative = @bitCast(result & 0x80 != 0);
            return cycles(op_table[op_code]);
        }
        fn op_rti(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.status = @bitCast((@as(u8, @bitCast(self.status)) & 0x30) | (self.pull_u8() & 0xcf));
            self.pc = self.pull_u16();
            return cycles(op_table[op_code]);
        }
        fn op_rts(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            _ = read_u8(0x0100 +% @as(u16, self.s));
            self.pc = self.pull_u16() +% 1;
            _ = read_u8(self.pc -% 1);
            return cycles(op_table[op_code]);
        }
        fn op_sbc(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            var result, const carry1 = @addWithOverflow(self.a, ~operand.value);
            result, const carry2 = @addWithOverflow(result, self.status.carry);

            self.status.carry = carry1 | carry2;
            self.status.zero = @bitCast(result == 0);
            self.status.overflow = @bitCast((result ^ self.a) & (result ^ ~operand.value) & 0x80 != 0);
            self.status.negative = @bitCast(result & 0x80 != 0);

            self.a = result;
            return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
        }
        fn op_sec(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.status.carry = 1;
            return cycles(op_table[op_code]);
        }
        fn op_sed(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.status.decimal = 1;
            return cycles(op_table[op_code]);
        }
        fn op_sei(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.status.interruptDisable = 1;
            return cycles(op_table[op_code]);
        }
        fn op_sta(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            write_u8(operand.address.?, self.a);
            return cycles(op_table[op_code]);
        }
        fn op_stx(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            write_u8(operand.address.?, self.x);
            return cycles(op_table[op_code]);
        }
        fn op_sty(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            write_u8(operand.address.?, self.y);
            return cycles(op_table[op_code]);
        }
        fn op_tax(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.x = self.a;
            self.status.zero = @bitCast(self.x == 0);
            self.status.negative = @bitCast(self.x & 0x80 != 0);
            return cycles(op_table[op_code]);
        }
        fn op_tay(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.y = self.a;
            self.status.zero = @bitCast(self.y == 0);
            self.status.negative = @bitCast(self.y & 0x80 != 0);
            return cycles(op_table[op_code]);
        }
        fn op_tsx(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.x = self.s;
            self.status.zero = @bitCast(self.x == 0);
            self.status.negative = @bitCast(self.x & 0x80 != 0);
            return cycles(op_table[op_code]);
        }
        fn op_txa(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.a = self.x;
            self.status.zero = @bitCast(self.a == 0);
            self.status.negative = @bitCast(self.a & 0x80 != 0);
            return cycles(op_table[op_code]);
        }
        fn op_txs(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.s = self.x;
            return cycles(op_table[op_code]);
        }
        fn op_tya(self: *Self, op_code: u8) u8 {
            _ = read_u8(self.pc);
            self.a = self.y;
            self.status.zero = @bitCast(self.a == 0);
            self.status.negative = @bitCast(self.a & 0x80 != 0);
            return cycles(op_table[op_code]);
        }

        inline fn push_u8(self: *Self, value: u8) void {
            write_u8(0x0100 +% @as(u16, self.s), value);
            self.s -%= 1;
        }
        inline fn push_u16(self: *Self, value: u16) void {
            self.push_u8(@truncate(value >> 8));
            self.push_u8(@truncate(value & 0x00ff));
        }
        inline fn pull_u8(self: *Self) u8 {
            _ = read_u8(0x0100 +% @as(u16, self.s));
            self.s +%= 1;
            return read_u8(0x0100 +% @as(u16, self.s));
        }
        inline fn pull_u16(self: *Self) u16 {
            self.s +%= 1;
            const lo = @as(u16, read_u8(0x0100 +% @as(u16, self.s)));
            self.s +%= 1;
            const hi = @as(u16, read_u8(0x0100 +% @as(u16, self.s)));
            return hi << 8 | lo;
        }
        inline fn read_stack_u8(self: *Self) u8 {
            return read_u8(0x0100 +% @as(u16, self.s));
        }

        inline fn fetch_operand(self: *Self, op: Operation) Operand {
            return op.@"1".?(self);
        }
        inline fn cycles(op: Operation) u8 {
            return op.@"2";
        }
        inline fn execute(self: *Self, op: Operation, op_code: u8) u8 {
            return op.@"0"(self, op_code);
        }
        fn @"accumulator mode"(self: *Self) Operand {
            _ = read_u8(self.pc);
            return .{ .value = self.a };
        }
        fn @"#immediate mode"(self: *Self) Operand {
            return .{ .value = self.read_next_u8() };
        }
        fn @"zero page mode"(self: *Self) Operand {
            const address = self.read_next_u8();
            return .{ .address = address, .value = read_u8(address), .page_crossed = false };
        }
        fn @"zero page mode: write"(self: *Self) Operand {
            const address = self.read_next_u8();
            return .{ .address = address, .value = 0, .page_crossed = false };
        }
        fn @"zero page,x mode"(self: *Self) Operand {
            const index = self.read_next_u8();
            _ = read_u8(index);
            const address = index +% self.x;
            return .{ .address = address, .value = read_u8(address), .page_crossed = false };
        }
        fn @"zero page,x mode: write"(self: *Self) Operand {
            const index = self.read_next_u8();
            _ = read_u8(index);
            const address = index +% self.x;
            return .{ .address = address, .value = 0, .page_crossed = false };
        }
        fn @"zero page,y mode"(self: *Self) Operand {
            const index = self.read_next_u8();
            _ = read_u8(index);
            const address = index +% self.y;
            return .{ .address = address, .value = read_u8(address), .page_crossed = false };
        }
        fn @"zero page,y mode: write"(self: *Self) Operand {
            const index = self.read_next_u8();
            _ = read_u8(index);
            const address = index +% self.y;
            return .{ .address = address, .value = 0, .page_crossed = false };
        }
        fn @"absolute mode"(self: *Self) Operand {
            const address = self.read_next_u16();
            return .{ .address = address, .value = read_u8(address), .page_crossed = false };
        }
        fn @"absolute mode: write"(self: *Self) Operand {
            const address = self.read_next_u16();
            return .{ .address = address, .value = 0, .page_crossed = false };
        }
        fn @"absolute,x mode"(self: *Self) Operand {
            const lo = @as(u16, self.read_next_u8());
            const hi = @as(u16, self.read_next_u8()) << 8;
            const address = (hi | lo) +% self.x;
            const address_without_carry = hi + ((lo + self.x) & 0x00ff);
            const page_crossed = address & 0xff00 != hi;
            if (page_crossed) {
                _ = read_u8(address_without_carry);
            }
            return .{ .address = address, .value = read_u8(address), .page_crossed = page_crossed };
        }
        fn @"absolute,x mode: write"(self: *Self) Operand {
            const lo = @as(u16, self.read_next_u8());
            const hi = @as(u16, self.read_next_u8()) << 8;
            const address = (hi | lo) +% self.x;
            const address_without_carry = hi + ((lo + self.x) & 0x00ff);
            const page_crossed = address & 0xff00 != hi;
            if (page_crossed) {
                _ = read_u8(address_without_carry);
            } else {
                _ = read_u8(address);
            }
            return .{ .address = address, .value = 0, .page_crossed = page_crossed };
        }
        fn @"absolute,y mode"(self: *Self) Operand {
            const lo = @as(u16, self.read_next_u8());
            const hi = @as(u16, self.read_next_u8()) << 8;
            const address = (hi | lo) +% self.y;
            const address_without_carry = hi + ((lo + self.y) & 0x00ff);
            const page_crossed = address & 0xff00 != hi;
            if (page_crossed) {
                _ = read_u8(address_without_carry);
            }
            return .{ .address = address, .value = read_u8(address), .page_crossed = page_crossed };
        }
        fn @"absolute,y mode: write"(self: *Self) Operand {
            const lo = @as(u16, self.read_next_u8());
            const hi = @as(u16, self.read_next_u8()) << 8;
            const address = (hi | lo) +% self.y;
            const address_without_carry = hi + ((lo + self.y) & 0x00ff);
            const page_crossed = address & 0xff00 != hi;
            if (page_crossed) {
                _ = read_u8(address_without_carry);
            } else {
                _ = read_u8(address);
            }

            return .{ .address = address, .value = 0, .page_crossed = page_crossed };
        }
        fn @"(indirect,x) mode"(self: *Self) Operand {
            const index = self.read_next_u8();
            _ = read_u8(index);
            const lo = @as(u16, read_u8(index +% self.x));
            const hi = @as(u16, read_u8(index +% self.x +% 1)) << 8;
            const address = hi | lo;
            return .{ .address = address, .value = read_u8(address), .page_crossed = false };
        }
        fn @"(indirect,x) mode: write"(self: *Self) Operand {
            const index = self.read_next_u8();
            _ = read_u8(index);
            const lo = @as(u16, read_u8(index +% self.x));
            const hi = @as(u16, read_u8(index +% self.x +% 1)) << 8;
            const address = hi | lo;
            return .{ .address = address, .value = 0, .page_crossed = false };
        }
        fn @"(indirect),y mode"(self: *Self) Operand {
            const base_index = self.read_next_u8();
            const lo = @as(u16, read_u8(base_index));
            const hi = @as(u16, read_u8(base_index +% 1)) << 8;
            const address = (hi | lo) +% self.y;
            const address_without_carry = hi + ((lo + self.y) & 0x00ff);
            const page_crossed = address & 0xff00 != hi;
            if (page_crossed) {
                _ = read_u8(address_without_carry);
            }
            return .{ .address = address, .value = read_u8(address), .page_crossed = page_crossed };
        }
        fn @"(indirect),y mode: write"(self: *Self) Operand {
            const base_index = self.read_next_u8();
            const lo = @as(u16, read_u8(base_index));
            const hi = @as(u16, read_u8(base_index +% 1)) << 8;
            const address = (hi | lo) +% self.y;
            const address_without_carry = hi + ((lo + self.y) & 0x00ff);
            const page_crossed = address & 0xff00 != hi;
            if (page_crossed) {
                _ = read_u8(address_without_carry);
            } else {
                _ = read_u8(address);
            }
            return .{ .address = address, .value = 0, .page_crossed = page_crossed };
        }
    };
}

////////////////////////////////////////////////////////////////////////////////
/// Tests
////////////////////////////////////////////////////////////////////////////////
const supported_ops = [_]struct { u8, bool }{
    .{ 0xaa, true },
    .{ 0xa8, true },
    .{ 0xba, true },
    .{ 0x8a, true },
    .{ 0x9a, true },
    .{ 0x98, true },

    .{ 0x84, true },
    .{ 0x94, true },
    .{ 0x8c, true },

    .{ 0x86, true },
    .{ 0x96, true },
    .{ 0x8e, true },

    .{ 0x85, true },
    .{ 0x95, true },
    .{ 0x8d, true },
    .{ 0x9d, true },
    .{ 0x99, true },
    .{ 0x81, true },
    .{ 0x91, true },

    .{ 0x78, true },
    .{ 0xf8, true },
    .{ 0x38, true },

    .{ 0xe9, true },
    .{ 0xe5, true },
    .{ 0xf5, true },
    .{ 0xed, true },
    .{ 0xfd, true },
    .{ 0xf9, true },
    .{ 0xe1, true },
    .{ 0xf1, true },

    .{ 0x60, true },
    .{ 0x40, true },

    .{ 0x6a, true },
    .{ 0x66, true },
    .{ 0x76, true },
    .{ 0x6e, true },
    // FIXME: check why there is a double read?
    .{ 0x7e, false },

    .{ 0x2a, true },
    .{ 0x26, true },
    .{ 0x36, true },
    .{ 0x2e, true },
    // FIXME: check why there is a double read?
    .{ 0x3e, false },

    .{ 0x28, true },
    .{ 0x68, true },
    .{ 0x08, true },
    .{ 0x48, true },

    .{ 0x09, true },
    .{ 0x05, true },
    .{ 0x15, true },
    .{ 0x0d, true },
    .{ 0x1d, true },
    .{ 0x19, true },
    .{ 0x01, true },
    .{ 0x11, true },

    .{ 0xea, true },

    .{ 0x4a, true },
    .{ 0x46, true },
    .{ 0x56, true },
    .{ 0x4e, true },
    // FIXME: check why there is a double read?
    .{ 0x5e, false },

    .{ 0xa0, true },
    .{ 0xa4, true },
    .{ 0xb4, true },
    .{ 0xac, true },
    .{ 0xbc, true },

    .{ 0xa2, true },
    .{ 0xa6, true },
    .{ 0xb6, true },
    .{ 0xae, true },
    .{ 0xbe, true },

    .{ 0xa9, true },
    .{ 0xa5, true },
    .{ 0xb5, true },
    .{ 0xad, true },
    .{ 0xbd, true },
    .{ 0xb9, true },
    .{ 0xa1, true },
    .{ 0xb1, true },

    .{ 0x20, true },
    .{ 0x4c, true },
    .{ 0x6c, true },

    .{ 0xe8, true },
    .{ 0xc8, true },

    .{ 0x49, true },
    .{ 0x45, true },
    .{ 0x55, true },
    .{ 0x4d, true },
    .{ 0x5d, true },
    .{ 0x59, true },
    .{ 0x41, true },
    .{ 0x51, true },

    .{ 0x88, true },
    .{ 0xca, true },

    .{ 0xe6, true },
    .{ 0xf6, true },
    .{ 0xee, true },
    // FIXME: check why there is a double read?
    .{ 0xfe, false },

    .{ 0xc6, true },
    .{ 0xd6, true },
    .{ 0xce, true },
    // FIXME: check why there is a double read?
    .{ 0xde, false },

    .{ 0xc0, true },
    .{ 0xc4, true },
    .{ 0xcc, true },

    .{ 0xe0, true },
    .{ 0xe4, true },
    .{ 0xec, true },

    .{ 0xc9, true },
    .{ 0xc5, true },
    .{ 0xd5, true },
    .{ 0xcd, true },
    .{ 0xdd, true },
    .{ 0xd9, true },
    .{ 0xc1, true },
    .{ 0xd1, true },

    .{ 0xb8, true },
    .{ 0x58, true },
    .{ 0xd8, true },
    .{ 0x18, true },

    .{ 0x00, true },
    .{ 0x2c, true },
    .{ 0x24, true },

    .{ 0x70, true },
    .{ 0x50, true },
    .{ 0x10, true },
    .{ 0xd0, true },
    .{ 0x30, true },
    .{ 0xf0, true },
    .{ 0xb0, true },
    .{ 0x90, true },

    // FIXME: check why there is a double read?
    .{ 0x1e, false },
    .{ 0x0e, true },
    .{ 0x16, true },
    .{ 0x06, true },
    .{ 0x0a, true },

    .{ 0x31, true },
    .{ 0x21, true },
    .{ 0x39, true },
    .{ 0x3d, true },
    .{ 0x2d, true },
    .{ 0x35, true },
    .{ 0x25, true },
    .{ 0x29, true },

    .{ 0x69, true },
    .{ 0x65, true },
    .{ 0x75, true },
    .{ 0x6d, true },
    .{ 0x7d, true },
    .{ 0x79, true },
    .{ 0x61, true },
    .{ 0x71, true },
};

const TestCase = struct {
    name: []u8,
    initial: CpuState,
    final: CpuState,
    cycles: []BusEvent,
};

const BusEvent = struct {
    u16, // address
    u8, // value
    []const u8, // "read" or "write"
};

const CpuState = struct {
    pc: u16,
    s: u8,
    a: u8,
    x: u8,
    y: u8,
    p: u8,
    ram: []struct { u16, u8 },
};

fn loadTestSuite(file_buffer: []u8, allocator: Allocator, dir: std.fs.Dir, op: u8) !std.json.Parsed([]TestCase) {
    var file = blk: {
        var buf: [10]u8 = undefined;
        const filename = try std.fmt.bufPrint(&buf, "{x:02}.json", .{op});
        const file = try dir.openFile(filename, .{});
        break :blk file;
    };
    defer file.close();
    const len = try file.readAll(file_buffer);
    return try std.json.parseFromSlice([]TestCase, allocator, file_buffer[0..len], std.json.ParseOptions{
        .ignore_unknown_fields = true,
    });
}

var test_memory: []u8 = undefined;
var bus_events: std.ArrayList(BusEvent) = undefined;

inline fn test_read_u8(address: u16) u8 {
    const val = test_memory[address];
    bus_events.appendAssumeCapacity(.{ address, val, "read" });
    return val;
}
inline fn test_read_u16(address: u16) u16 {
    const lo = test_read_u8(address);
    const hi = test_read_u8(address +% 1);
    return (@as(u16, hi) << 8) + lo;
}
inline fn test_write_u8(address: u16, value: u8) void {
    test_memory[address] = value;
    bus_events.appendAssumeCapacity(.{ address, value, "write" });
}

test "nes6502 test suite" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    test_memory = try allocator.alloc(u8, 1 << 16);
    bus_events = try std.ArrayList(BusEvent).initCapacity(allocator, 32);
    const file_buffer = try allocator.alloc(u8, 10 * (2 << 20)); // 10

    const Cpu = Nes6502(test_read_u8, test_read_u16, test_write_u8);
    Cpu.init();
    const expectCpuState = struct {
        fn call(expected: CpuState, cpu: Cpu) !void {
            try std.testing.expectEqual(cpu.status, @as(StatusFlags, @bitCast(expected.p)));
            try std.testing.expectEqual(cpu.pc, expected.pc);
            try std.testing.expectEqual(cpu.s, expected.s);
            try std.testing.expectEqual(cpu.a, expected.a);
            try std.testing.expectEqual(cpu.x, expected.x);
            try std.testing.expectEqual(cpu.y, expected.y);
        }
    }.call;
    const expectMemoryState = struct {
        fn call(expected: []struct { u16, u8 }, actual: []u8) !void {
            for (expected) |addrVal| {
                try std.testing.expectEqual(actual[addrVal[0]], addrVal[1]);
            }
        }
    }.call;
    const expectBusEvents = struct {
        fn call(expected: []BusEvent, actual: []BusEvent) !void {
            try std.testing.expectEqualDeep(expected, actual);
        }
    }.call;

    const dir = try std.fs.cwd().openDir("65x02/nes6502/v1", .{ .iterate = true });
    for (supported_ops) |supported_op| {
        const op, const check_cycles = supported_op;

        std.debug.print("Running test suite for operation: {x:02}\n", .{op});
        const test_suite = try loadTestSuite(file_buffer, allocator, dir, op);
        defer test_suite.deinit();

        for (test_suite.value, 0..) |testCase, index| {
            bus_events.clearRetainingCapacity();
            const initial = testCase.initial;
            const expected = testCase.final;
            var cpu = Cpu{
                .status = @bitCast(initial.p),
                .pc = initial.pc,
                .s = initial.s,
                .a = initial.a,
                .x = initial.x,
                .y = initial.y,
            };
            for (initial.ram) |entry| {
                const addr, const value = entry;
                test_memory[addr] = value;
            }

            _ = cpu.execute_next_op();

            if (check_cycles) {
                expectBusEvents(testCase.cycles, bus_events.items) catch |err| {
                    std.debug.print("Unexpected bus events for test case #{d}: {s}\n", .{ index, testCase.name });
                    std.debug.print("Expected bus events:\n", .{});
                    for (testCase.cycles) |event| {
                        std.debug.print("{s} @{x:04} => {x:02}\n", .{ event.@"2", event.@"0", event.@"1" });
                    }
                    std.debug.print("Actual bus events:\n", .{});
                    for (bus_events.items) |event| {
                        std.debug.print("{s} @{x:04} => {x:02}\n", .{ event.@"2", event.@"0", event.@"1" });
                    }
                    return err;
                };
            }
            expectCpuState(expected, cpu) catch |err| {
                std.debug.print("Unexpected CPU state for test case #{d}: {s}\n", .{ index, testCase.name });
                std.debug.print("\tExpected\tActual\n", .{});
                std.debug.print("PC\t{x:04}\t\t{x:04}\n", .{ expected.pc, cpu.pc });
                std.debug.print("a\t{x:02}\t\t{x:02}\n", .{ expected.a, cpu.a });
                std.debug.print("x\t{x:02}\t\t{x:02}\n", .{ expected.x, cpu.x });
                std.debug.print("y\t{x:02}\t\t{x:02}\n", .{ expected.y, cpu.y });
                std.debug.print("s\t{x:02}\t\t{x:02}\n", .{ expected.s, cpu.s });
                std.debug.print("p\t{x:02}\t\t{x:02}\n", .{ expected.p, @as(u8, @bitCast(cpu.status)) });
                const expected_status: StatusFlags = @bitCast(expected.p);
                std.debug.print("carry\t{d}\t\t{d}\n", .{ expected_status.carry, cpu.status.carry });
                std.debug.print("zero\t{d}\t\t{d}\n", .{ expected_status.zero, cpu.status.zero });
                std.debug.print("int\t{d}\t\t{d}\n", .{ expected_status.interruptDisable, cpu.status.interruptDisable });
                std.debug.print("dec\t{d}\t\t{d}\n", .{ expected_status.decimal, cpu.status.decimal });
                std.debug.print("b\t{d}\t\t{d}\n", .{ expected_status.b, cpu.status.b });
                std.debug.print("overfl\t{d}\t\t{d}\n", .{ expected_status.overflow, cpu.status.overflow });
                std.debug.print("neg\t{d}\t\t{d}\n", .{ expected_status.negative, cpu.status.negative });
                return err;
            };
            expectMemoryState(expected.ram, test_memory) catch |err| {
                std.debug.print("Unexpected memory state for test case #{d}: {s}\n", .{ index, testCase.name });
                std.debug.print("\tExpected\tActual\n", .{});
                for (expected.ram) |entry| {
                    const address, const value = entry;
                    const actual = test_memory[address];
                    std.debug.print("{s}{x:04}\t{x:02}\t\t{x:02}\n", .{ if (actual != value) "*" else " ", address, value, actual });
                }
                return err;
            };
        }
    }
}
