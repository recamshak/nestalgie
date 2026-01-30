const math = @import("std").math;
const Envelope = @import("./envelope.zig").Envelope;

pub fn Dmc(comptime Bus: type) type {
    return struct {
        bus: *Bus,

        sample_start_address: u16 = 0,
        sample_length: u16 = 0,
        sample_rate: u16 = 0,

        samples_remaining: u16 = 0,
        next_sample_address: u16 = 0,

        sample_buffer: ?u8 = null,
        bits_remaining: u8 = 0,
        shift_register: u8 = 0,
        silence: bool = true,
        output: u8 = 0,

        enabled: bool = false,

        pub const period_table = [_]u12{ 4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068 };

        const Self = @This();

        pub fn tick(self: *Self) void {
            if (!self.silence) {
                if (self.shift_register & 1 == 0 and self.output >= 2) {
                    self.output -= 2;
                } else if (self.shift_register & 1 == 1 and self.output <= 125) {
                    self.output += 2;
                }
                self.shift_register >>= 1;
            }

            self.bits_remaining -|= 1;
            if (self.bits_remaining == 0) {
                self.bits_remaining = 8;
                if (self.sample_buffer) |sample| {
                    self.silence = false;
                    self.shift_register = sample;
                    self.fetchNextSample();
                } else {
                    self.silence = true;
                }
            }
        }

        fn fetchNextSample(self: *Self) void {
            if (self.samples_remaining > 0) {
                self.samples_remaining -= 1;
                self.sample_buffer = self.bus.read_u8(self.next_sample_address);
                self.next_sample_address +%= 1;
                if (self.next_sample_address == 0) {
                    self.next_sample_address = 0x8000;
                }
            } else {
                self.sample_buffer = null;
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
    };
}
