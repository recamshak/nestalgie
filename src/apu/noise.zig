const math = @import("std").math;
const Envelope = @import("./envelope.zig").Envelope;

mode: u1 = 0,
shift_register: u15 = 1,
envelope: Envelope = .{ .constant = 0 },
period: u12 = 0,
counter: u12 = 0,
length_counter: u8 = 0,
length_counter_halt: bool = false,
enabled: bool = false,

pub const period_table = [_]u12{ 4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068 };

const Self = @This();

pub fn tick(self: *Self) void {
    if (self.counter == 0) {
        const feedback = switch (self.mode) {
            0 => (self.shift_register & 0x01) ^ ((self.shift_register & 0x02) >> 1),
            1 => (self.shift_register & 0x01) ^ ((self.shift_register & 0x40) >> 6),
        };
        self.shift_register = (self.shift_register >> 1) | (feedback << 14);
        self.counter = self.period;
    } else {
        self.counter -= 1;
    }
}

pub fn clockLengthCounter(self: *Self) void {
    if (self.length_counter > 0 and !self.length_counter_halt) {
        self.length_counter -= 1;
    }
}

pub fn getSample(self: *Self) u8 {
    if (self.length_counter == 0 or (self.shift_register & 1) == 0) return 0;
    return self.envelope.volume();
}
