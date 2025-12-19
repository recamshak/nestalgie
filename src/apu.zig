const std = @import("std");

pub const APU = struct {
    pub inline fn read_u8(_: *APU, _: u16) u8 {
        return 0;
    }
    pub inline fn write_u8(_: *APU, _: u16, _: u8) void {}
};
