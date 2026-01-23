const math = @import("std").math;

const std = @import("std");

timer_period: u11 = 0,
timer_value: u11 = 0,

linear_counter: u7 = 0,
linear_counter_reload_value: u7 = 0,
linear_counter_reload_flag: bool = false,
control_flag: bool = false, // Also acts as length counter halt flag

length_counter: u8 = 0,
sequencer_step: u5 = 0,
enabled: bool = false,

const Self = @This();

const sequence_table = [_]u4{
    15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5,  4,  3,  2,  1,  0,
    0,  1,  2,  3,  4,  5,  6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
};

pub fn clockLengthCounter(self: *Self) void {
    if (self.enabled and !self.control_flag and self.length_counter > 0) {
        self.length_counter -= 1;
    }
}

pub fn clockLinearCounter(self: *Self) void {
    if (self.linear_counter_reload_flag) {
        self.linear_counter = self.linear_counter_reload_value;
    } else if (self.linear_counter > 0) {
        self.linear_counter -= 1;
    }

    if (!self.control_flag) {
        self.linear_counter_reload_flag = false;
    }
}

pub fn tick(self: *Self) void {
    if (self.timer_value == 0) {
        self.timer_value = self.timer_period;

        if (self.linear_counter > 0 and self.length_counter > 0) {
            self.sequencer_step +%= 1;
        }
    } else {
        self.timer_value -= 1;
    }
}

pub fn getSample(self: *const Self) u4 {
    return sequence_table[self.sequencer_step];
}

pub fn setEnabled(self: *Self, enabled: bool) void {
    self.enabled = enabled;
    if (!enabled) {
        self.length_counter = 0;
    }
}

pub fn getStatus(self: *const Self) bool {
    return self.length_counter > 0;
}
