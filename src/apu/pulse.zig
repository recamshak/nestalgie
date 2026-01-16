const math = @import("std").math;
const Envelope = @import("./envelope.zig").Envelope;

pub const Sweep = packed struct(u8) {
    shift: u3 = 0,
    negate: bool = false,
    period: u3 = 0,
    enabled: bool = false,
};
pub const Duty = enum(u2) {
    one_eighth = 0,
    one_quarter = 1,
    one_half = 2,
    three_quarter = 3,
};

const waveform_sequences = []u8{
    0b0100_0000,
    0b0110_0000,
    0b0111_1000,
    0b1001_1111,
};

timer_counter: u16 = 0,
timer_reset_counter: u16 = 0,
envelope: Envelope = .{ .constant = 0 },
duty: Duty = .one_eighth,
sweep: Sweep = .{},
sweep_cycle: u8 = 0,
length_counter: u8 = 0,
length_counter_halt: bool = false,
waveform_sequence: u8 = 0,

const Self = @This();

pub fn tick(self: *Self) void {
    self.timer_counter -|= 1;
    if (self.timer_counter == 0) {
        self.timer_counter = self.timer_reset_counter + 1;
        self.waveform_sequence = math.rotl(u8, self.waveform_sequence, 1);
    }
}

pub fn clockLengthCounter(self: *Self) void {
    if (self.length_counter > 0 and !self.length_counter_halt) {
        self.length_counter -= 1;
    }
}

pub fn clockSweep(self: *Self) void {
    if (self.sweep_cycle > 0) {
        self.sweep_cycle -= 1;
    } else {}
}
