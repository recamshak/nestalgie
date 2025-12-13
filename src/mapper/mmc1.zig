const std = @import("std");

pub const MMC1 = struct {
    pub inline fn read_u8(_: *MMC1, address: u16) u8 {
        std.log.info("NROM reading {X:04}\n", .{address});
        return 0;
    }
    pub inline fn write_u8(_: *MMC1, address: u16, value: u8) void {
        std.log.info("NROM writing {X:02} @{X:04}\n", .{ value, address });
    }
};
