const std = @import("std");
const INes = @import("../ines.zig").INes;

pub const UXROM = struct {
    prg_banks: [][]u8,
    active_prg_bank: []u8,
    fixed_prg_bank: []u8,

    chr_rom: []u8,
    vram: []u8,

    pub inline fn read_u8(self: *UXROM, address: u16) u8 {
        return if (address & 0x4000 == 0)
            self.active_prg_bank[address & 0x3FFF]
        else
            self.fixed_prg_bank[address & 0x3FFF];
    }

    pub inline fn write_u8(self: *UXROM, _: u16, value: u8) void {
        self.active_prg_bank = self.prg_banks[value];
    }

    pub inline fn ppu_read_u8(self: *UXROM, address: u16) u8 {
        return switch (address & 0x2000) {
            0x0000 => self.chr_rom[address & 0x1FFF],
            0x2000 => self.vram[address & 0x07FF],
            else => unreachable,
        };
    }
    pub inline fn ppu_write_u8(self: *UXROM, address: u16, value: u8) void {
        switch (address & 0x2000) {
            0x0000 => self.chr_rom[address & 0x1FFF] = value,
            0x2000 => self.vram[address & 0x07FF] = value,
            else => unreachable,
        }
    }

    pub fn getPointer(self: *UXROM, address: u16) []u8 {
        return switch (address & 0xC000) {
            // switchable bank
            0x8000 => self.active_prg_bank[address & 0x3FFF ..],
            // non-switchable bank (always the last)
            0xC000 => self.fixed_prg_bank[address & 0x3FFF ..],
            else => unreachable,
        };
    }

    pub fn from_ines(allocator: std.mem.Allocator, ines: *const INes) !UXROM {
        std.log.info("Header: {any}", .{ines.header});
        const chr_rom = if (ines.chr_rom.len == 0) try allocator.alloc(u8, 8 * 1024) else ines.chr_rom;
        const vram = try allocator.alloc(u8, 2048);
        const banks = try allocator.alloc([]u8, ines.header.prg_rom_size);
        for (0..ines.header.prg_rom_size) |i| {
            banks[i] = ines.prg_rom[i * 16384 .. (i + 1) * 16384];
        }
        return .{
            .prg_banks = banks,
            .active_prg_bank = banks[0],
            .fixed_prg_bank = banks[banks.len - 1],
            .chr_rom = chr_rom,
            .vram = vram,
        };
    }
};
