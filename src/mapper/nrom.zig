const std = @import("std");
const INes = @import("../ines.zig").INes;

pub const NROM = struct {
    prg_rom: []u8,
    chr_rom: []u8,
    address_mask: u16,

    pub inline fn read_u8(self: *NROM, address: u16) u8 {
        std.log.info("NROM reading {X:04}", .{address});
        return self.prg_rom[address & self.address_mask];
    }
    pub inline fn write_u8(self: *NROM, address: u16, value: u8) void {
        std.log.info("NROM writing {X:02} @{X:04}", .{ value, address });
        self.prg_rom[address & self.address_mask] = value;
    }

    pub inline fn ppu_read_u8(self: *NROM, address: u16) u8 {
        std.log.info("NROM PPU reading {X:04}", .{address});
        return self.chr_rom[address];
    }
    pub inline fn ppu_write_u8(self: *NROM, address: u16, value: u8) void {
        std.log.info("NROM PPU writing {X:02} @{X:04}", .{ value, address });
        self.chr_rom[address] = value;
    }

    pub fn from_ines(ines: *const INes) !NROM {
        return .{
            .prg_rom = ines.prg_rom,
            .chr_rom = ines.chr_rom,
            .address_mask = if (ines.header.prg_rom_size == 1) 0x3FFF else 0x7FFF,
        };
    }
};
