const std = @import("std");

pub const APU = struct {
    pub inline fn read_u8(_: *APU, address: u16) u8 {
        std.log.info("APU reading {X:04}\n", .{address});
        return 0;
    }
    pub inline fn write_u8(_: *APU, address: u16, value: u8) void {
        std.log.info("APU writing {X:02} @{X:04}\n", .{ value, address });
    }
};
