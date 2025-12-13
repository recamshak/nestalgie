const NROM = @import("mapper/nrom.zig").NROM;
const MMC1 = @import("mapper/mmc1.zig").MMC1;
const INes = @import("ines.zig").INes;
const std = @import("std");

pub const CartridgeError = error{UnsupportedMapper};

pub const Cartridge = union(enum) {
    nrom: NROM,
    mmc1: MMC1,

    pub fn read_u8(self: *Cartridge, address: u16) u8 {
        return switch (self.*) {
            inline else => |*m| m.read_u8(address),
        };
    }

    pub fn write_u8(self: *Cartridge, address: u16, value: u8) void {
        switch (self.*) {
            inline else => |*m| m.write_u8(address, value),
        }
    }

    pub fn ppu_read_u8(self: *Cartridge, address: u16) u8 {
        return switch (self.*) {
            inline else => |*m| m.ppu_read_u8(address),
        };
    }

    pub fn ppu_write_u8(self: *Cartridge, address: u16, value: u8) void {
        switch (self.*) {
            inline else => |*m| m.ppu_write_u8(address, value),
        }
    }

    pub fn from_ines(_: std.mem.Allocator, ines: *const INes) !Cartridge {
        switch (ines.mapper_id()) {
            0 => return .{ .nrom = try NROM.from_ines(ines) },
            else => {
                std.log.err("Unsupported mapper with ID: {d}", .{ines.mapper_id()});
                return CartridgeError.UnsupportedMapper;
            },
        }
    }
};
