const math = @import("std").math;
const Envelope = @import("./envelope.zig").Envelope;

pub const Duty = enum(u2) {
    one_eighth = 0,
    one_quarter = 1,
    one_half = 2,
    three_quarter = 3,
};

const Sweep = struct {
    enabled: bool = false,
    mode: SweepMode = .increase,
    shift: u3 = 0,
    period: u8 = 0,
    counter: u8 = 0,
};

const SweepMode = enum {
    increase,
    ones_complement,
    twos_complement,
};

const waveform_sequences = [_]u8{
    0b0100_0000,
    0b0110_0000,
    0b0111_1000,
    0b1001_1111,
};

period_counter: u16 = 0,
period: u16 = 0,
envelope: Envelope = .{ .constant = 0 },
sweep: Sweep = .{},
length_counter: u8 = 0,
length_counter_halt: bool = false,
waveform_sequence: u8 = 0,

const Self = @This();

pub fn tick(self: *Self) void {
    self.period_counter -|= 1;
    if (self.period_counter == 0) {
        self.period_counter = self.period;
        self.waveform_sequence = math.rotl(u8, self.waveform_sequence, 1);
    }
}

pub fn clockLengthCounter(self: *Self) void {
    if (self.length_counter > 0 and !self.length_counter_halt) {
        self.length_counter -= 1;
    }
}

pub fn clockSweep(self: *Self) void {
    if (self.sweep.counter > 0) {
        self.sweep.counter -= 1;
    } else {
        if (self.sweep.enabled) {
            const sweep = (self.period & 0x07FF) >> self.sweep.shift;
            switch (self.sweep.mode) {
                .increase => self.period +%= sweep,
                .ones_complement => self.period -|= sweep + 1,
                .twos_complement => self.period -|= sweep,
            }
            if (self.period < 8 or self.period > 0x07FF) {
                self.sweep.enabled = false;
            }
        }
        self.sweep.counter = self.sweep.period;
    }
    // TODO: check https://forums.nesdev.org/viewtopic.php?p=1402&sid=51e61abf6df9a49d6c7b9f63bdf26092#p1402
}

pub fn getSample(self: *Self) u8 {
    if (self.length_counter == 0 or self.period < 8 or self.period > 0x07FF) return 0;
    return self.envelope.volume() * (self.waveform_sequence & 1);
}

pub fn setDuty(self: *Self, duty: Duty) void {
    self.waveform_sequence = waveform_sequences[@intFromEnum(duty)];
}
