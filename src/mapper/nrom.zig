const std = @import("std");
const INes = @import("../ines.zig").INes;

pub const NROM = struct {
    prg_rom: []u8,
    chr_rom: []u8,
    address_mask: u16,
    vram: []u8,

    pub inline fn read_u8(self: *NROM, address: u16) u8 {
        return self.prg_rom[address & self.address_mask];
    }
    pub inline fn write_u8(self: *NROM, address: u16, value: u8) void {
        self.prg_rom[address & self.address_mask] = value;
    }

    pub inline fn ppu_read_u8(self: *NROM, address: u16) u8 {
        return switch (address & 0x2000) {
            0x0000 => self.chr_rom[address & 0x1FFF],
            0x2000 => self.vram[address & 0x07FF],
            else => unreachable,
        };
    }
    pub inline fn ppu_write_u8(self: *NROM, address: u16, value: u8) void {
        switch (address & 0x2000) {
            0x0000 => self.chr_rom[address & 0x1FFF] = value,
            0x2000 => self.vram[address & 0x07FF] = value,
            else => unreachable,
        }
    }

    pub fn getPointer(self: *NROM, address: u16) []u8 {
        return self.prg_rom[address & self.address_mask ..];
    }

    pub fn from_ines(allocator: std.mem.Allocator, ines: *const INes) !NROM {
        const chr_rom = if (ines.chr_rom.len == 0) try allocator.alloc(u8, 8096) else ines.chr_rom;
        const vram = try allocator.alloc(u8, 2048);
        return .{
            .prg_rom = ines.prg_rom,
            .chr_rom = chr_rom,
            .address_mask = if (ines.header.prg_rom_size == 1) 0x3FFF else 0x7FFF,
            .vram = vram,
        };
    }
};
