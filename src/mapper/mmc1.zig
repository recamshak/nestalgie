const std = @import("std");

pub const MMC1 = struct {
    pub inline fn read_u8(_: *MMC1, address: u16) u8 {
        std.log.info("MMC1 reading {X:04}\n", .{address});
        return 0;
    }
    pub inline fn write_u8(_: *MMC1, address: u16, value: u8) void {
        std.log.info("MMC1 writing {X:02} @{X:04}\n", .{ value, address });
    }
    pub inline fn ppu_read_u8(_: *MMC1, address: u16) u8 {
        std.log.info("MMC1 PPU reading {X:04}\n", .{address});
        return 0;
    }
    pub inline fn ppu_write_u8(_: *MMC1, address: u16, value: u8) void {
        std.log.info("MMC1 PPU writing {X:02} @{X:04}\n", .{ value, address });
    }

    pub fn getPointer(_: *MMC1, address: u16) []u8 {
        std.log.info("MMC1 get pointer @{X:04}\n", .{address});
        return &[0]u8{};
    }
};
