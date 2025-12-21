const Self = @This();
pub const Status = packed struct(u8) {
    a: u1 = 0,
    b: u1 = 0,
    select: u1 = 0,
    start: u1 = 0,
    up: u1 = 0,
    down: u1 = 0,
    left: u1 = 0,
    right: u1 = 0,
};

fetch: *const fn () Status,
shift_register: u8 = 0,

// $4016 write
pub fn write(self: *Self, value: u8) void {
    if (value & 1 == 1) {
        self.shift_register = @bitCast(self.fetch());
    }
}

// $4016 read
pub fn readController1(self: *Self) u8 {
    defer self.shift_register >>= 1;
    return self.shift_register & 1;
}

// $4017 read
pub fn readController2(_: *Self) u8 {
    return 0;
}
