const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("tracy");

const Allocator = std.mem.Allocator;

const StatusFlags = packed struct(u8) {
    carry: u1 = 0,
    zero: u1 = 0,
    interrupt_disable: u1 = 0,
    decimal: u1 = 0,
    b: u1 = 0,
    _pad: u1 = 1,
    overflow: u1 = 0,
    negative: u1 = 0,
};

pub fn Nes6502(comptime Bus: type) type {
    return struct {
        const Self = @This();
        const OpFn = fn (self: *Self, op_code: u8) u8;
        const Operation = struct {
            *const OpFn,
            ?*const fn (self: *Self) Operand,
            u8,
        };
        const Operand = struct {
            value: u8,
            address: ?u16 = null,
            page_crossed: bool = false,
        };

        bus: *Bus,
        pc: u16 = 0,
        a: u8 = 0,
        x: u8 = 0,
        y: u8 = 0,
        s: u8 = 0xFD,
        status: StatusFlags = StatusFlags{},

        irq: u1 = 0,
        nmi: u1 = 0,

        nmi_triggered: bool = false,

        pub fn set_nmi(self: *Self, value: u1) void {
            if (self.nmi == 0 and value == 1) {
                self.nmi_triggered = true;
            }
            self.nmi = value;
        }

        const stp = Operation{ op_stp, null, 0 };
        const not_supported = Operation{ op_not_supported, null, 0 };

        var op_table: [256]Operation = [_]Operation{
            // 0x00
            Operation{ op_brk, null, 7 },
            Operation{ op_ora, @"(indirect,x) mode", 6 },
            stp,
            not_supported,
            Operation{ op_nop, @"zero page mode", 3 },
            Operation{ op_ora, @"zero page mode", 3 },
            Operation{ op_asl, @"zero page mode", 5 },
            not_supported,
            Operation{ op_php, null, 3 },
            Operation{ op_ora, @"#immediate mode", 2 },
            Operation{ op_asl, @"accumulator mode", 2 },
            not_supported,
            Operation{ op_nop, @"absolute mode", 4 },
            Operation{ op_ora, @"absolute mode", 4 },
            Operation{ op_asl, @"absolute mode", 6 },
            not_supported,

            // 0x10
            Operation{ op_bpl, null, 0 },
            Operation{ op_ora, @"(indirect),y mode", 5 },
            stp,
            not_supported,
            Operation{ op_nop, @"zero page,x mode", 4 },
            Operation{ op_ora, @"zero page,x mode", 4 },
            Operation{ op_asl, @"zero page,x mode", 6 },
            not_supported,
            Operation{ op_clc, null, 2 },
            Operation{ op_ora, @"absolute,y mode", 4 },
            Operation{ op_nop, null, 2 },
            not_supported,
            Operation{ op_nop, @"absolute,x mode", 4 },
            Operation{ op_ora, @"absolute,x mode", 4 },
            Operation{ op_asl, @"absolute,x mode", 7 },
            not_supported,

            // 0x20
            Operation{ op_jsr, @"absolute mode", 6 },
            Operation{ op_and, @"(indirect,x) mode", 6 },
            stp,
            not_supported,
            Operation{ op_bit, @"zero page mode", 3 },
            Operation{ op_and, @"zero page mode", 3 },
            Operation{ op_rol, @"zero page mode", 5 },
            not_supported,
            Operation{ op_plp, null, 4 },
            Operation{ op_and, @"#immediate mode", 2 },
            Operation{ op_rol, @"accumulator mode", 2 },
            not_supported,
            Operation{ op_bit, @"absolute mode", 4 },
            Operation{ op_and, @"absolute mode", 4 },
            Operation{ op_rol, @"absolute mode", 6 },
            not_supported,

            // 0x30
            Operation{ op_bmi, null, 0 },
            Operation{ op_and, @"(indirect),y mode", 5 },
            stp,
            not_supported,
            Operation{ op_nop, @"zero page,x mode", 4 },
            Operation{ op_and, @"zero page,x mode", 4 },
            Operation{ op_rol, @"zero page,x mode", 6 },
            not_supported,
            Operation{ op_sec, null, 2 },
            Operation{ op_and, @"absolute,y mode", 4 },
            Operation{ op_nop, null, 2 },
            not_supported,
            Operation{ op_nop, @"absolute,x mode", 4 },
            Operation{ op_and, @"absolute,x mode", 4 },
            Operation{ op_rol, @"absolute,x mode", 7 },
            not_supported,

            // 0x40
            Operation{ op_rti, null, 6 },
            Operation{ op_eor, @"(indirect,x) mode", 6 },
            stp,
            not_supported,
            Operation{ op_nop, @"zero page mode", 3 },
            Operation{ op_eor, @"zero page mode", 3 },
            Operation{ op_lsr, @"zero page mode", 5 },
            not_supported,
            Operation{ op_pha, null, 3 },
            Operation{ op_eor, @"#immediate mode", 2 },
            Operation{ op_lsr, @"accumulator mode", 2 },
            not_supported,
            Operation{ op_jmp, null, 3 },
            Operation{ op_eor, @"absolute mode", 4 },
            Operation{ op_lsr, @"absolute mode", 6 },
            not_supported,

            // 0x50
            Operation{ op_bvc, null, 0 },
            Operation{ op_eor, @"(indirect),y mode", 5 },
            stp,
            not_supported,
            Operation{ op_nop, @"zero page,x mode", 4 },
            Operation{ op_eor, @"zero page,x mode", 4 },
            Operation{ op_lsr, @"zero page,x mode", 6 },
            not_supported,
            Operation{ op_cli, null, 2 },
            Operation{ op_eor, @"absolute,y mode", 4 },
            Operation{ op_nop, null, 2 },
            not_supported,
            Operation{ op_nop, @"absolute,x mode", 4 },
            Operation{ op_eor, @"absolute,x mode", 4 },
            Operation{ op_lsr, @"absolute,x mode", 7 },
            not_supported,

            // 0x60
            Operation{ op_rts, null, 6 },
            Operation{ op_adc, @"(indirect,x) mode", 6 },
            stp,
            not_supported,
            Operation{ op_nop, @"zero page mode", 3 },
            Operation{ op_adc, @"zero page mode", 3 },
            Operation{ op_ror, @"zero page mode", 5 },
            not_supported,
            Operation{ op_pla, null, 4 },
            Operation{ op_adc, @"#immediate mode", 2 },
            Operation{ op_ror, @"accumulator mode", 2 },
            not_supported,
            Operation{ op_jmp_indirect, null, 5 },
            Operation{ op_adc, @"absolute mode", 4 },
            Operation{ op_ror, @"absolute mode", 6 },
            not_supported,

            // 0x70
            Operation{ op_bvs, null, 0 },
            Operation{ op_adc, @"(indirect),y mode", 5 },
            stp,
            not_supported,
            Operation{ op_nop, @"zero page,x mode", 4 },
            Operation{ op_adc, @"zero page,x mode", 4 },
            Operation{ op_ror, @"zero page,x mode", 6 },
            not_supported,
            Operation{ op_sei, null, 2 },
            Operation{ op_adc, @"absolute,y mode", 4 },
            Operation{ op_nop, null, 2 },
            not_supported,
            Operation{ op_nop, @"absolute,x mode", 4 },
            Operation{ op_adc, @"absolute,x mode", 4 },
            Operation{ op_ror, @"absolute,x mode", 7 },
            not_supported,

            // 0x80
            Operation{ op_nop, @"#immediate mode", 2 },
            Operation{ op_sta, @"(indirect,x) mode: write", 6 },
            Operation{ op_nop, @"#immediate mode", 2 },
            not_supported,
            Operation{ op_sty, @"zero page mode: write", 3 },
            Operation{ op_sta, @"zero page mode: write", 3 },
            Operation{ op_stx, @"zero page mode: write", 3 },
            not_supported,
            Operation{ op_dey, null, 2 },
            Operation{ op_nop, @"#immediate mode", 2 },
            Operation{ op_txa, null, 2 },
            not_supported,
            Operation{ op_sty, @"absolute mode: write", 4 },
            Operation{ op_sta, @"absolute mode: write", 4 },
            Operation{ op_stx, @"absolute mode: write", 4 },
            not_supported,

            // 0x90
            Operation{ op_bcc, null, 0 },
            Operation{ op_sta, @"(indirect),y mode: write", 6 },
            stp,
            not_supported,
            Operation{ op_sty, @"zero page,x mode: write", 4 },
            Operation{ op_sta, @"zero page,x mode: write", 4 },
            Operation{ op_stx, @"zero page,y mode: write", 4 },
            not_supported,
            Operation{ op_tya, null, 2 },
            Operation{ op_sta, @"absolute,y mode: write", 5 },
            Operation{ op_txs, null, 2 },
            not_supported,
            not_supported,
            Operation{ op_sta, @"absolute,x mode: write", 5 },
            not_supported,
            not_supported,

            // 0xA0
            Operation{ op_ldy, @"#immediate mode", 2 },
            Operation{ op_lda, @"(indirect,x) mode", 6 },
            Operation{ op_ldx, @"#immediate mode", 2 },
            not_supported,
            Operation{ op_ldy, @"zero page mode", 3 },
            Operation{ op_lda, @"zero page mode", 3 },
            Operation{ op_ldx, @"zero page mode", 3 },
            not_supported,
            Operation{ op_tay, null, 2 },
            Operation{ op_lda, @"#immediate mode", 2 },
            Operation{ op_tax, null, 2 },
            not_supported,
            Operation{ op_ldy, @"absolute mode", 4 },
            Operation{ op_lda, @"absolute mode", 4 },
            Operation{ op_ldx, @"absolute mode", 4 },
            not_supported,

            // 0xB0
            Operation{ op_bcs, null, 0 },
            Operation{ op_lda, @"(indirect),y mode", 5 },
            stp,
            not_supported,
            Operation{ op_ldy, @"zero page,x mode", 4 },
            Operation{ op_lda, @"zero page,x mode", 4 },
            Operation{ op_ldx, @"zero page,y mode", 4 },
            not_supported,
            Operation{ op_clv, null, 2 },
            Operation{ op_lda, @"absolute,y mode", 4 },
            Operation{ op_tsx, null, 2 },
            not_supported,
            Operation{ op_ldy, @"absolute,x mode", 4 },
            Operation{ op_lda, @"absolute,x mode", 4 },
            Operation{ op_ldx, @"absolute,y mode", 4 },
            not_supported,

            // 0xC0
            Operation{ op_cpy, @"#immediate mode", 2 },
            Operation{ op_cmp, @"(indirect,x) mode", 6 },
            Operation{ op_nop, @"#immediate mode", 2 },
            not_supported,
            Operation{ op_cpy, @"zero page mode", 3 },
            Operation{ op_cmp, @"zero page mode", 3 },
            Operation{ op_dec, @"zero page mode", 5 },
            not_supported,
            Operation{ op_iny, null, 2 },
            Operation{ op_cmp, @"#immediate mode", 2 },
            Operation{ op_dex, null, 2 },
            not_supported,
            Operation{ op_cpy, @"absolute mode", 4 },
            Operation{ op_cmp, @"absolute mode", 4 },
            Operation{ op_dec, @"absolute mode", 6 },
            not_supported,

            // 0xD0
            Operation{ op_bne, null, 0 },
            Operation{ op_cmp, @"(indirect),y mode", 5 },
            stp,
            not_supported,
            Operation{ op_nop, @"zero page,x mode", 4 },
            Operation{ op_cmp, @"zero page,x mode", 4 },
            Operation{ op_dec, @"zero page,x mode", 6 },
            not_supported,
            Operation{ op_cld, null, 2 },
            Operation{ op_cmp, @"absolute,y mode", 4 },
            Operation{ op_nop, null, 2 },
            not_supported,
            Operation{ op_nop, @"absolute,x mode", 4 },
            Operation{ op_cmp, @"absolute,x mode", 4 },
            Operation{ op_dec, @"absolute,x mode", 7 },
            not_supported,

            // 0xE0
            Operation{ op_cpx, @"#immediate mode", 2 },
            Operation{ op_sbc, @"(indirect,x) mode", 6 },
            Operation{ op_nop, @"#immediate mode", 2 },
            not_supported,
            Operation{ op_cpx, @"zero page mode", 3 },
            Operation{ op_sbc, @"zero page mode", 3 },
            Operation{ op_inc, @"zero page mode", 5 },
            not_supported,
            Operation{ op_inx, null, 2 },
            Operation{ op_sbc, @"#immediate mode", 2 },
            Operation{ op_nop, null, 2 },
            not_supported,
            Operation{ op_cpx, @"absolute mode", 4 },
            Operation{ op_sbc, @"absolute mode", 4 },
            Operation{ op_inc, @"absolute mode", 6 },
            not_supported,

            // 0xF0
            Operation{ op_beq, null, 0 },
            Operation{ op_sbc, @"(indirect),y mode", 5 },
            stp,
            not_supported,
            Operation{ op_nop, @"zero page,x mode", 4 },
            Operation{ op_sbc, @"zero page,x mode", 4 },
            Operation{ op_inc, @"zero page,x mode", 6 },
            not_supported,
            Operation{ op_sed, null, 2 },
            Operation{ op_sbc, @"absolute,y mode", 4 },
            Operation{ op_nop, null, 2 },
            not_supported,
            Operation{ op_nop, @"absolute,x mode", 4 },
            Operation{ op_sbc, @"absolute,x mode", 4 },
            Operation{ op_inc, @"absolute,x mode", 7 },
            not_supported,
        };

        inline fn write_u8(self: *Self, address: u16, value: u8) void {
            return self.bus.write_u8(address, value);
        }

        inline fn read_u8(self: *Self, address: u16) u8 {
            return self.bus.read_u8(address);
        }

        inline fn read_u16(self: *Self, address: u16) u16 {
            const lo = self.read_u8(address);
            const hi = self.read_u8(address +% 1);
            return (@as(u16, hi) << 8) | lo;
        }

        inline fn read_next_u8(self: *Self) u8 {
            defer self.pc +%= 1;
            return self.read_u8(self.pc);
        }

        inline fn read_next_u16(self: *Self) u16 {
            defer self.pc +%= 2;
            return self.read_u16(self.pc);
        }

        pub fn execute_next_op(self: *Self) u8 {
            // TODO: IRQ
            if (self.nmi_triggered) {
                //std.log.debug("NMI triggered", .{});
                self.nmi_triggered = false;
                self.push_u16(self.pc);
                self.push_u8(@bitCast(self.status));
                self.status.b = 0;
                self.pc = self.read_u16(0xFFFA);
                return 5;
            } else {
                const op_code = self.read_next_u8();
                const op = op_table[op_code];
                //std.log.debug("execute op {X:02} @{X:04}", .{ op_code, self.pc -% 1 });
                return self.execute(op, op_code);
            }
        }

        fn op_nop(self: *Self, op_code: u8) u8 {
            if (op_table[op_code].@"1" != null) {
                const operand = self.fetch_operand(op_table[op_code]);
                return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
            } else {
                _ = self.read_u8(self.pc);
                return cycles(op_table[op_code]);
            }
        }

        fn op_not_supported(_: *Self, op_code: u8) u8 {
            var buf: [2]u8 = undefined;
            _ = std.fmt.bufPrint(&buf, "{X:02}", .{op_code}) catch unreachable;
            @panic("Operation not supported: 0x" ++ buf);
        }

        fn op_stp(_: *Self, _: u8) u8 {
            @panic("CPU halt.");
        }

        fn load(comptime register: []const u8) OpFn {
            return struct {
                fn op(self: *Self, op_code: u8) u8 {
                    const operand = self.fetch_operand(op_table[op_code]);
                    @field(self, register) = operand.value;
                    self.status.zero = @bitCast(@field(self, register) == 0);
                    self.status.negative = @bitCast(@field(self, register) & 0x80 != 0);
                    return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
                }
            }.op;
        }
        const op_lda = load("a");
        const op_ldx = load("x");
        const op_ldy = load("y");

        fn store(comptime register: []const u8) OpFn {
            return struct {
                fn op(self: *Self, op_code: u8) u8 {
                    const operand = self.fetch_operand(op_table[op_code]);
                    self.write_u8(operand.address.?, @field(self, register));
                    return cycles(op_table[op_code]);
                }
            }.op;
        }
        const op_sta = store("a");
        const op_stx = store("x");
        const op_sty = store("y");

        fn add_with_carry(comptime invert: bool) OpFn {
            return struct {
                fn op(self: *Self, op_code: u8) u8 {
                    const operand = self.fetch_operand(op_table[op_code]);
                    const value = if (invert) ~operand.value else operand.value;
                    var result, const carry1 = @addWithOverflow(self.a, value);
                    result, const carry2 = @addWithOverflow(result, self.status.carry);

                    self.status.carry = carry1 | carry2;
                    self.status.zero = @bitCast(result == 0);
                    self.status.overflow = @bitCast((result ^ self.a) & (result ^ value) & 0x80 != 0);
                    self.status.negative = @bitCast(result & 0x80 != 0);
                    self.a = result;

                    return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
                }
            }.op;
        }
        const op_adc = add_with_carry(false);
        const op_sbc = add_with_carry(true);

        fn increment_memory(comptime amount: i3) OpFn {
            return struct {
                fn op(self: *Self, op_code: u8) u8 {
                    const operand = self.fetch_operand(op_table[op_code]);
                    const result = if (amount >= 0) operand.value +% amount else operand.value -% (-amount);
                    self.write_u8(operand.address.?, operand.value);
                    self.write_u8(operand.address.?, result);
                    self.status.zero = @bitCast(result == 0);
                    self.status.negative = @bitCast(result & 0x80 != 0);
                    return cycles(op_table[op_code]);
                }
            }.op;
        }
        fn increment_register(comptime register: []const u8, comptime amount: i3) OpFn {
            return struct {
                fn op(self: *Self, op_code: u8) u8 {
                    _ = self.read_u8(self.pc);
                    const result = if (amount >= 0) @field(self, register) +% amount else @field(self, register) -% (-amount);
                    @field(self, register) = result;
                    self.status.zero = @bitCast(result == 0);
                    self.status.negative = @bitCast(result & 0x80 != 0);
                    return cycles(op_table[op_code]);
                }
            }.op;
        }
        const op_inc = increment_memory(1);
        const op_dec = increment_memory(-1);
        const op_inx = increment_register("x", 1);
        const op_dex = increment_register("x", -1);
        const op_iny = increment_register("y", 1);
        const op_dey = increment_register("y", -1);

        const BitwiseOp = enum { And, Or, Xor };
        fn bitwise_op(comptime operation: BitwiseOp) OpFn {
            return struct {
                fn op(self: *Self, op_code: u8) u8 {
                    const operand = self.fetch_operand(op_table[op_code]);
                    const result = switch (operation) {
                        .And => self.a & operand.value,
                        .Or => self.a | operand.value,
                        .Xor => self.a ^ operand.value,
                    };
                    self.status.zero = @bitCast(result == 0);
                    self.status.negative = @bitCast(result & 0x80 != 0);
                    self.a = result;
                    return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
                }
            }.op;
        }
        const op_and = bitwise_op(.And);
        const op_ora = bitwise_op(.Or);
        const op_eor = bitwise_op(.Xor);

        fn op_bit(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]).value;
            const result = self.a & operand;
            self.status.zero = @bitCast(result == 0);
            self.status.overflow = @bitCast(operand & 0x40 != 0);
            self.status.negative = @bitCast(operand & 0x80 != 0);

            return cycles(op_table[op_code]);
        }

        fn op_asl(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            const result, const carry = @shlWithOverflow(operand.value, 1);
            if (operand.address) |address| {
                self.write_u8(address, operand.value);
                self.write_u8(address, result);
            } else {
                self.a = result;
            }
            self.status.zero = @bitCast(result == 0);
            self.status.carry = carry;
            self.status.negative = @bitCast(result & 0x80 != 0);
            return cycles(op_table[op_code]);
        }

        fn branch(comptime flag: []const u8, comptime condition: u1) OpFn {
            return struct {
                fn op(self: *Self, _: u8) u8 {
                    const offset = @as(i8, @bitCast(self.read_next_u8()));
                    if (@field(self.status, flag) != condition) return 2;

                    const new_pc: u16 = @bitCast(@as(i16, @bitCast(self.pc)) +% offset);
                    const page_crossed = self.pc ^ new_pc & 0xff00 != 0;
                    if (builtin.is_test) {
                        _ = self.read_u8(self.pc);
                        if (page_crossed) {
                            const new_pc_without_carry: u16 = (self.pc & 0xff00) | (new_pc & 0x00ff);
                            _ = self.read_u8(new_pc_without_carry);
                        }
                    }
                    self.pc = new_pc;
                    return @as(u8, 3) + @as(u1, @bitCast(page_crossed));
                }
            }.op;
        }
        const op_bcc = branch("carry", 0);
        const op_bcs = branch("carry", 1);
        const op_beq = branch("zero", 1);
        const op_bne = branch("zero", 0);
        const op_bpl = branch("negative", 0);
        const op_bmi = branch("negative", 1);
        const op_bvc = branch("overflow", 0);
        const op_bvs = branch("overflow", 1);

        fn compare(comptime register: []const u8) OpFn {
            return struct {
                fn op(self: *Self, op_code: u8) u8 {
                    const value = @field(self, register);
                    const operand = self.fetch_operand(op_table[op_code]);
                    self.status.carry = @bitCast(value >= operand.value);
                    self.status.zero = @bitCast(value == operand.value);
                    self.status.negative = @bitCast((value -% operand.value) & 0x80 != 0);
                    return cycles(op_table[op_code]) + @as(u1, @bitCast(operand.page_crossed));
                }
            }.op;
        }
        const op_cmp = compare("a");
        const op_cpx = compare("x");
        const op_cpy = compare("y");

        fn op_jmp(self: *Self, op_code: u8) u8 {
            const address = self.read_next_u16();
            self.pc = address;
            return cycles(op_table[op_code]);
        }

        fn op_jmp_indirect(self: *Self, op_code: u8) u8 {
            const ptr = self.read_next_u16();
            if (ptr & 0x00ff == 0x00ff) {
                self.pc = @as(u16, self.read_u8(ptr)) | (@as(u16, self.read_u8(ptr & 0xff00)) << 8);
            } else {
                self.pc = self.read_u16(ptr);
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
        fn op_rts(self: *Self, op_code: u8) u8 {
            _ = self.read_u8(self.pc);
            _ = self.read_u8(0x0100 +% @as(u16, self.s));
            self.pc = self.pull_u16() +% 1;
            _ = self.read_u8(self.pc -% 1);
            return cycles(op_table[op_code]);
        }
        fn op_rti(self: *Self, op_code: u8) u8 {
            _ = self.read_u8(self.pc);
            self.status = @bitCast((@as(u8, @bitCast(self.status)) & 0x30) | (self.pull_u8() & 0xcf));
            self.pc = self.pull_u16();
            return cycles(op_table[op_code]);
        }
        fn op_brk(self: *Self, op_code: u8) u8 {
            _ = self.read_u8(self.pc);
            self.push_u16(self.pc +% 1);
            self.push_u8(@as(u8, @bitCast(self.status)) | 0x30);
            self.pc = self.read_u16(0xfffe);
            self.status.interrupt_disable = 1;
            return cycles(op_table[op_code]);
        }

        fn op_lsr(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            const result = operand.value >> 1;
            if (operand.address) |address| {
                self.write_u8(address, operand.value);
                self.write_u8(address, result);
            } else {
                self.a = result;
            }

            self.status.carry = @bitCast(operand.value & 0x01 != 0);
            self.status.zero = @bitCast(result == 0);
            self.status.negative = 0;
            return cycles(op_table[op_code]);
        }

        fn op_pha(self: *Self, op_code: u8) u8 {
            _ = self.read_u8(self.pc);
            self.push_u8(self.a);
            return cycles(op_table[op_code]);
        }
        fn op_php(self: *Self, op_code: u8) u8 {
            _ = self.read_u8(self.pc);
            self.push_u8(@as(u8, @bitCast(self.status)) | 0x30);
            return cycles(op_table[op_code]);
        }
        fn op_pla(self: *Self, op_code: u8) u8 {
            _ = self.read_u8(self.pc);
            self.a = self.pull_u8();
            self.status.zero = @bitCast(self.a == 0);
            self.status.negative = @bitCast(self.a & 0x80 != 0);
            return cycles(op_table[op_code]);
        }
        fn op_plp(self: *Self, op_code: u8) u8 {
            _ = self.read_u8(self.pc);
            const b = self.status.b;
            self.status = @bitCast(self.pull_u8() | 0x20);
            self.status.b = b;
            return cycles(op_table[op_code]);
        }
        fn op_rol(self: *Self, op_code: u8) u8 {
            const operand = self.fetch_operand(op_table[op_code]);
            const result = operand.value << 1 | @as(u8, self.status.carry);
            if (operand.address) |address| {
                self.write_u8(address, operand.value);
                self.write_u8(address, result);
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
                self.write_u8(address, operand.value);
                self.write_u8(address, result);
            } else {
                self.a = result;
            }
            self.status.carry = @bitCast(operand.value & 0x01 != 0);
            self.status.zero = @bitCast(result == 0);
            self.status.negative = @bitCast(result & 0x80 != 0);
            return cycles(op_table[op_code]);
        }
        fn set_flag(comptime flag_name: []const u8, comptime value: u1) OpFn {
            return struct {
                fn op(self: *Self, op_code: u8) u8 {
                    _ = self.read_u8(self.pc);
                    @field(self.status, flag_name) = value;
                    return cycles(op_table[op_code]);
                }
            }.op;
        }
        const op_clc = set_flag("carry", 0);
        const op_sec = set_flag("carry", 1);
        const op_cli = set_flag("interrupt_disable", 0);
        const op_sei = set_flag("interrupt_disable", 1);
        const op_cld = set_flag("decimal", 0);
        const op_sed = set_flag("decimal", 1);
        const op_clv = set_flag("overflow", 0);

        fn transfer(comptime register_from: []const u8, comptime register_to: []const u8, comptime update_status: bool) OpFn {
            return struct {
                fn op(self: *Self, op_code: u8) u8 {
                    _ = self.read_u8(self.pc);
                    @field(self, register_to) = @field(self, register_from);
                    if (update_status) {
                        self.status.zero = @bitCast(@field(self, register_to) == 0);
                        self.status.negative = @bitCast(@field(self, register_to) & 0x80 != 0);
                    }
                    return cycles(op_table[op_code]);
                }
            }.op;
        }
        const op_tax = transfer("a", "x", true);
        const op_tay = transfer("a", "y", true);
        const op_tsx = transfer("s", "x", true);
        const op_txs = transfer("x", "s", false);
        const op_txa = transfer("x", "a", true);
        const op_tya = transfer("y", "a", true);

        inline fn push_u8(self: *Self, value: u8) void {
            self.write_u8(0x0100 +% @as(u16, self.s), value);
            self.s -%= 1;
        }
        inline fn push_u16(self: *Self, value: u16) void {
            self.push_u8(@truncate(value >> 8));
            self.push_u8(@truncate(value & 0x00ff));
        }
        inline fn pull_u8(self: *Self) u8 {
            _ = self.read_u8(0x0100 +% @as(u16, self.s));
            self.s +%= 1;
            return self.read_u8(0x0100 +% @as(u16, self.s));
        }
        inline fn pull_u16(self: *Self) u16 {
            self.s +%= 1;
            const lo = @as(u16, self.read_u8(0x0100 +% @as(u16, self.s)));
            self.s +%= 1;
            const hi = @as(u16, self.read_u8(0x0100 +% @as(u16, self.s)));
            return hi << 8 | lo;
        }
        inline fn read_stack_u8(self: *Self) u8 {
            return self.read_u8(0x0100 +% @as(u16, self.s));
        }

        inline fn fetch_operand(self: *Self, op: Operation) Operand {
            return op.@"1".?(self);
        }
        inline fn cycles(op: Operation) u8 {
            return op.@"2";
        }
        inline fn execute(self: *Self, op: Operation, op_code: u8) u8 {
            const zone = tracy.initZone(@src(), .{ .name = "Execute OP" });
            defer zone.deinit();
            return op.@"0"(self, op_code);
        }

        // TODO: clean this mess
        fn @"accumulator mode"(self: *Self) Operand {
            _ = self.read_u8(self.pc);
            return .{ .value = self.a };
        }
        fn @"#immediate mode"(self: *Self) Operand {
            return .{ .value = self.read_next_u8() };
        }
        fn @"zero page mode"(self: *Self) Operand {
            const address = self.read_next_u8();
            return .{ .address = address, .value = self.read_u8(address), .page_crossed = false };
        }
        fn @"zero page mode: write"(self: *Self) Operand {
            const address = self.read_next_u8();
            return .{ .address = address, .value = 0, .page_crossed = false };
        }
        fn @"zero page,x mode"(self: *Self) Operand {
            const index = self.read_next_u8();
            _ = self.read_u8(index);
            const address = index +% self.x;
            return .{ .address = address, .value = self.read_u8(address), .page_crossed = false };
        }
        fn @"zero page,x mode: write"(self: *Self) Operand {
            const index = self.read_next_u8();
            _ = self.read_u8(index);
            const address = index +% self.x;
            return .{ .address = address, .value = 0, .page_crossed = false };
        }
        fn @"zero page,y mode"(self: *Self) Operand {
            const index = self.read_next_u8();
            _ = self.read_u8(index);
            const address = index +% self.y;
            return .{ .address = address, .value = self.read_u8(address), .page_crossed = false };
        }
        fn @"zero page,y mode: write"(self: *Self) Operand {
            const index = self.read_next_u8();
            _ = self.read_u8(index);
            const address = index +% self.y;
            return .{ .address = address, .value = 0, .page_crossed = false };
        }
        fn @"absolute mode"(self: *Self) Operand {
            const address = self.read_next_u16();
            return .{ .address = address, .value = self.read_u8(address), .page_crossed = false };
        }
        fn @"absolute mode: write"(self: *Self) Operand {
            const address = self.read_next_u16();
            return .{ .address = address, .value = 0, .page_crossed = false };
        }
        fn @"absolute,x mode"(self: *Self) Operand {
            const lo = @as(u16, self.read_next_u8());
            const hi = @as(u16, self.read_next_u8()) << 8;
            const address = (hi | lo) +% self.x;
            const address_without_carry = hi | (address & 0x00ff);
            const page_crossed = address & 0xff00 != hi;
            if (page_crossed) {
                _ = self.read_u8(address_without_carry);
            }
            return .{ .address = address, .value = self.read_u8(address), .page_crossed = page_crossed };
        }
        fn @"absolute,x mode: write"(self: *Self) Operand {
            const lo = @as(u16, self.read_next_u8());
            const hi = @as(u16, self.read_next_u8()) << 8;
            const address = (hi | lo) +% self.x;
            const address_without_carry = hi | (address & 0x00ff);
            const page_crossed = address & 0xff00 != hi;
            if (page_crossed) {
                _ = self.read_u8(address_without_carry);
            } else {
                _ = self.read_u8(address);
            }
            return .{ .address = address, .value = 0, .page_crossed = page_crossed };
        }
        fn @"absolute,y mode"(self: *Self) Operand {
            const lo = @as(u16, self.read_next_u8());
            const hi = @as(u16, self.read_next_u8()) << 8;
            const address = (hi | lo) +% self.y;
            const address_without_carry = hi | (address & 0x00ff);
            const page_crossed = address & 0xff00 != hi;
            if (page_crossed) {
                _ = self.read_u8(address_without_carry);
            }
            return .{ .address = address, .value = self.read_u8(address), .page_crossed = page_crossed };
        }
        fn @"absolute,y mode: write"(self: *Self) Operand {
            const lo = @as(u16, self.read_next_u8());
            const hi = @as(u16, self.read_next_u8()) << 8;
            const address = (hi | lo) +% self.y;
            const address_without_carry = hi | (address & 0x00ff);
            const page_crossed = address & 0xff00 != hi;
            if (page_crossed) {
                _ = self.read_u8(address_without_carry);
            } else {
                _ = self.read_u8(address);
            }

            return .{ .address = address, .value = 0, .page_crossed = page_crossed };
        }
        fn @"(indirect,x) mode"(self: *Self) Operand {
            const index = self.read_next_u8();
            _ = self.read_u8(index);
            const lo = @as(u16, self.read_u8(index +% self.x));
            const hi = @as(u16, self.read_u8(index +% self.x +% 1)) << 8;
            const address = hi | lo;
            return .{ .address = address, .value = self.read_u8(address), .page_crossed = false };
        }
        fn @"(indirect,x) mode: write"(self: *Self) Operand {
            const index = self.read_next_u8();
            _ = self.read_u8(index);
            const lo = @as(u16, self.read_u8(index +% self.x));
            const hi = @as(u16, self.read_u8(index +% self.x +% 1)) << 8;
            const address = hi | lo;
            return .{ .address = address, .value = 0, .page_crossed = false };
        }
        fn @"(indirect),y mode"(self: *Self) Operand {
            const base_index = self.read_next_u8();
            const lo = @as(u16, self.read_u8(base_index));
            const hi = @as(u16, self.read_u8(base_index +% 1)) << 8;
            const address = (hi | lo) +% self.y;
            const address_without_carry = hi | (address & 0x00ff);
            const page_crossed = address & 0xff00 != hi;
            if (page_crossed) {
                _ = self.read_u8(address_without_carry);
            }
            return .{ .address = address, .value = self.read_u8(address), .page_crossed = page_crossed };
        }
        fn @"(indirect),y mode: write"(self: *Self) Operand {
            const base_index = self.read_next_u8();
            const lo = @as(u16, self.read_u8(base_index));
            const hi = @as(u16, self.read_u8(base_index +% 1)) << 8;
            const address = (hi | lo) +% self.y;
            const address_without_carry = hi + (address & 0x00ff);
            const page_crossed = address & 0xff00 != hi;
            if (page_crossed) {
                _ = self.read_u8(address_without_carry);
            } else {
                _ = self.read_u8(address);
            }
            return .{ .address = address, .value = 0, .page_crossed = page_crossed };
        }
    };
}

////////////////////////////////////////////////////////////////////////////////
/// Tests
////////////////////////////////////////////////////////////////////////////////
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

const TestBus = struct {
    memory: []u8,
    events: std.ArrayList(BusEvent),

    inline fn read_u8(self: *TestBus, address: u16) u8 {
        const val = self.memory[address];
        self.events.appendAssumeCapacity(.{ address, val, "read" });
        return val;
    }
    inline fn write_u8(self: *TestBus, address: u16, value: u8) void {
        self.memory[address] = value;
        self.events.appendAssumeCapacity(.{ address, value, "write" });
    }
};

fn loadTestSuite(file_buffer: []u8, allocator: Allocator, dir: std.fs.Dir, op: usize) !std.json.Parsed([]TestCase) {
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

test "nes6502 test suite" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var bus = TestBus{
        .memory = try allocator.alloc(u8, 1 << 16),
        .events = try std.ArrayList(BusEvent).initCapacity(allocator, 32),
    };
    const file_buffer = try allocator.alloc(u8, 10 * (2 << 20)); // 10Mb

    const Cpu = Nes6502(TestBus);
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
    for (0..256) |op_code| {
        var check_cycles = true;
        if (std.meta.eql(Cpu.op_table[op_code], Cpu.not_supported)) {
            std.debug.print("FIXME: Skipping unsuppored operation 0x{X:02}\n", .{op_code});
            continue;
        } else if (std.meta.eql(Cpu.op_table[op_code], Cpu.stp)) {
            std.debug.print("Skipping STP operation 0x{X:02}\n", .{op_code});
            continue;
        } else if (op_code == 0x1e or op_code == 0x3e or op_code == 0x5e or op_code == 0x7e or op_code == 0xde or op_code == 0xfe) {
            std.debug.print("FIXME: Disabling cycle checks for operation 0x{X:02}\n", .{op_code});
            check_cycles = false;
        }

        std.debug.print("Running test suite for operation 0x{X:02}\n", .{op_code});
        const test_suite = try loadTestSuite(file_buffer, allocator, dir, op_code);
        defer test_suite.deinit();

        for (test_suite.value, 0..) |testCase, index| {
            bus.events.clearRetainingCapacity();
            const initial = testCase.initial;
            const expected = testCase.final;
            var cpu = Cpu{
                .bus = &bus,
                .status = @bitCast(initial.p),
                .pc = initial.pc,
                .s = initial.s,
                .a = initial.a,
                .x = initial.x,
                .y = initial.y,
            };
            for (initial.ram) |entry| {
                const addr, const value = entry;
                bus.memory[addr] = value;
            }

            _ = cpu.execute_next_op();

            if (check_cycles) {
                expectBusEvents(testCase.cycles, bus.events.items) catch |err| {
                    std.debug.print("Unexpected bus events for test case #{d}: {s}\n", .{ index, testCase.name });
                    std.debug.print("Expected bus events:\n", .{});
                    for (testCase.cycles) |event| {
                        std.debug.print("{s} @{X:04} => {X:02}\n", .{ event.@"2", event.@"0", event.@"1" });
                    }
                    std.debug.print("Actual bus events:\n", .{});
                    for (bus.events.items) |event| {
                        std.debug.print("{s} @{X:04} => {X:02}\n", .{ event.@"2", event.@"0", event.@"1" });
                    }
                    return err;
                };
            }
            expectCpuState(expected, cpu) catch |err| {
                std.debug.print("Unexpected CPU state for test case #{d}: {s}\n", .{ index, testCase.name });
                std.debug.print("\tExpected\tActual\n", .{});
                std.debug.print("PC\t{X:04}\t\t{X:04}\n", .{ expected.pc, cpu.pc });
                std.debug.print("a\t{X:02}\t\t{X:02}\n", .{ expected.a, cpu.a });
                std.debug.print("x\t{X:02}\t\t{X:02}\n", .{ expected.x, cpu.x });
                std.debug.print("y\t{X:02}\t\t{X:02}\n", .{ expected.y, cpu.y });
                std.debug.print("s\t{X:02}\t\t{X:02}\n", .{ expected.s, cpu.s });
                std.debug.print("p\t{X:02}\t\t{X:02}\n", .{ expected.p, @as(u8, @bitCast(cpu.status)) });
                const expected_status: StatusFlags = @bitCast(expected.p);
                std.debug.print("carry\t{d}\t\t{d}\n", .{ expected_status.carry, cpu.status.carry });
                std.debug.print("zero\t{d}\t\t{d}\n", .{ expected_status.zero, cpu.status.zero });
                std.debug.print("int\t{d}\t\t{d}\n", .{ expected_status.interrupt_disable, cpu.status.interrupt_disable });
                std.debug.print("dec\t{d}\t\t{d}\n", .{ expected_status.decimal, cpu.status.decimal });
                std.debug.print("b\t{d}\t\t{d}\n", .{ expected_status.b, cpu.status.b });
                std.debug.print("overfl\t{d}\t\t{d}\n", .{ expected_status.overflow, cpu.status.overflow });
                std.debug.print("neg\t{d}\t\t{d}\n", .{ expected_status.negative, cpu.status.negative });
                return err;
            };
            expectMemoryState(expected.ram, bus.memory) catch |err| {
                std.debug.print("Unexpected memory state for test case #{d}: {s}\n", .{ index, testCase.name });
                std.debug.print("\tExpected\tActual\n", .{});
                for (expected.ram) |entry| {
                    const address, const value = entry;
                    const actual = bus.memory[address];
                    std.debug.print("{s}{X:04}\t{X:02}\t\t{X:02}\n", .{ if (actual != value) "*" else " ", address, value, actual });
                }
                return err;
            };
        }
    }
}
