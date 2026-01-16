const std = @import("std");
const Pulse = @import("./apu/pulse.zig");
const Envelope = @import("./apu/envelope.zig");

const EnvelopePayload = packed struct(u6) {
    // if disabled is true then this is the volume, otherwise it's the period
    period_or_volume: u4 = 0,
    disabled: bool = false,
    loop: bool = false,
};

const PulseCtrlPayload = packed struct(u8) {
    envelope: EnvelopePayload = .{},
    duty: Pulse.Duty = .one_eighth,
};

const FrameCtrlPayload = packed struct(u8) {
    _padding: u6 = 0,
    disable_frame_interrupt: bool = false,
    sequencer_mode: SequencerMode,
};

const LengthAndTimerHi = packed struct(u8) {
    timer_hi: u3,
    length_index: u5,
};

const SequencerMode = enum(u1) {
    FourSteps = 0,
    FiveSteps = 1,
};

const length_counters = [32]u8{
    0x0A, 0xFE,
    0x14, 0x02,
    0x28, 0x04,
    0x50, 0x06,
    0xA0, 0x08,
    0x3C, 0x0A,
    0x0E, 0x0C,
    0x1A, 0x0E,
    0x0C, 0x10,
    0x18, 0x12,
    0x30, 0x14,
    0x60, 0x16,
    0xC0, 0x18,
    0x48, 0x1A,
    0x10, 0x1C,
    0x20, 0x1E,
};

const sampleHandler = *const fn (sample: u8) void;
const ticks_between_sample: f64 = 40.58;

pub fn APU(comptime Cpu: type) type {
    return struct {
        const Self = @This();

        // Stores the number of CPU cycles elapsed in the current sequencer frame.
        // One frame runs for 29'830 or 37'287 CPU cycles for 4-step and 5-step sequence respectively.
        frame_tick: u16 = 0,

        sequencer_mode: SequencerMode = .FourSteps,
        disable_interrupt: bool = false,
        pulse1: Pulse = .{},
        pulse2: Pulse = .{},

        cpu: *Cpu,
        sample_handler: sampleHandler,
        sine_sample: u32 = 0,
        ticks_before_next_sample: f64 = ticks_between_sample,

        pub fn write_status(_: *Self) void {}
        pub fn read_status(_: *Self) void {}
        pub fn write_frame_counter(_: *Self) void {}

        // 0x4000
        pub fn write_pulse1_ctrl(self: *Self, value: PulseCtrlPayload) void {
            self.pulse1.envelope = switch (value.envelope.disabled) {
                true => .{ .constant = value.envelope.period_or_volume },
                false => .{ .decay = .{
                    .timer_counter = value.envelope.period_or_volume,
                    .timer_reset_counter = value.envelope.period_or_volume,
                    .repeat = value.envelope.loop,
                } },
            };
            self.pulse1.duty = value.duty;
        }
        // 0x4001
        pub fn write_pulse1_sweep(self: *Self, value: Pulse.Sweep) void {
            self.pulse1.sweep = value;
        }
        // 0x4002
        pub fn write_pulse1_timer_lo(self: *Self, value: u8) void {
            self.pulse1.timer_reset_counter = self.pulse1.timer_reset_counter & 0x700 | value;
        }
        // 0x4003
        pub fn write_pulse1_timer_hi(self: *Self, value: LengthAndTimerHi) void {
            self.pulse1.timer_reset_counter = self.pulse1.timer_reset_counter & 0x0FF | @as(u11, value.timer_hi) << 8;
            self.pulse1.length_counter = length_counters[value.length_index];
            self.pulse1.envelope.reset();
        }

        // 0x4004
        pub fn write_pulse2_ctrl(self: *Self, value: PulseCtrlPayload) void {
            self.pulse2.envelope = switch (value.envelope.disabled) {
                true => .{ .constant = value.envelope.period_or_volume },
                false => .{ .decay = .{
                    .timer_counter = value.envelope.period_or_volume,
                    .timer_reset_counter = value.envelope.period_or_volume,
                    .repeat = value.envelope.loop,
                } },
            };
            self.pulse2.duty = value.duty;
        }
        // 0x4005
        pub fn write_pulse2_sweep(self: *Self, value: Pulse.Sweep) void {
            self.pulse2.sweep = value;
        }
        // 0x4006
        pub fn write_pulse2_timer_lo(self: *Self, value: u8) void {
            self.pulse2.timer_reset_counter = self.pulse2.timer_reset_counter & 0x700 | value;
        }
        // 0x4007
        pub fn write_pulse2_timer_hi(self: *Self, value: LengthAndTimerHi) void {
            self.pulse2.timer_reset_counter = self.pulse2.timer_reset_counter & 0x0FF | @as(u11, value.timer_hi) << 8;
            self.pulse2.length_counter = length_counters[value.length_index];
            self.pulse2.envelope.reset();
        }

        pub fn write_triangle_ctrl(_: *Self) void {}
        pub fn write_triangle_timer_lo(_: *Self) void {}
        pub fn write_triangle_timer_hi(_: *Self) void {}

        pub fn write_noise_ctrl(_: *Self) void {}
        pub fn write_noise_period(_: *Self) void {}
        pub fn write_noise_length(_: *Self) void {}

        pub fn write_dmc_ctrl(_: *Self) void {}
        pub fn write_dmc_load(_: *Self) void {}
        pub fn write_dmc_address(_: *Self) void {}
        pub fn write_dmc_length(_: *Self) void {}

        // 0x4017
        pub fn write_frame_ctrl(self: *Self, value: FrameCtrlPayload) void {
            self.sequencer_mode = value.sequencer_mode;
            self.disable_interrupt = value.disable_frame_interrupt;
        }

        pub inline fn read_u8(_: *Self, _: u16) u8 {
            return 0;
        }
        pub inline fn write_u8(_: *Self, _: u16, _: u8) void {}

        pub fn clock_envelops(self: *Self) void {
            self.pulse1.envelope.tick();
            self.pulse2.envelope.tick();
            // TODO: add other channels

        }

        pub fn clock_all_channels(self: *Self) void {
            self.pulse1.tick();
            self.pulse2.tick();
            // TODO: add other channels
        }

        pub fn clock_length_counter_and_sweep_units(self: *Self) void {
            self.pulse1.clockLengthCounter();
            self.pulse2.clockLengthCounter();
            // TODO: add other channels
        }

        pub fn generate_sample(self: *Self) u8 {
            const freq: f64 = 440.0;
            const sampling_freq: f64 = 44_100.0;
            const sample = @as(f64, @floatFromInt(self.sine_sample));
            self.sine_sample = (self.sine_sample + 1) % 44100;
            return @intFromFloat(255 * ((@sin(2 * std.math.pi * sample * freq / sampling_freq) + 1.0) / 2.0));
        }

        // This needs to be called every CPU cycle.
        // A sample is emitted every 40.58 CPU cycle. (1'789'773 / 44'100)
        pub fn tick(self: *Self) void {
            // every 2 ticks, call tick on each channel
            if (self.frame_tick % 2 == 0) {
                self.clock_all_channels();
            }

            self.ticks_before_next_sample -= 1;
            // every 40.58 ticks, generate a sample
            if (self.ticks_before_next_sample <= 0.0) {
                const sample = self.generate_sample();
                self.sample_handler(sample);
                self.ticks_before_next_sample += ticks_between_sample;
            }

            // every 7457.5 ticks, progress the sequencer
            self.frame_tick += 1;
            switch (self.frame_tick) {
                // step 1
                7457 => {
                    self.clock_envelops();
                    if (self.sequencer_mode == .FiveSteps) {
                        self.clock_length_counter_and_sweep_units();
                    }
                },
                // step 2
                14915 => {
                    self.clock_envelops();
                    if (self.sequencer_mode == .FourSteps) {
                        self.clock_length_counter_and_sweep_units();
                    }
                },
                // step 3
                22372 => {
                    self.clock_envelops();
                    if (self.sequencer_mode == .FiveSteps) {
                        self.clock_length_counter_and_sweep_units();
                    }
                },
                // step 4
                29830 => {
                    self.clock_envelops();
                    if (self.sequencer_mode == .FourSteps) {
                        self.clock_length_counter_and_sweep_units();
                        if (!self.disable_interrupt) {
                            self.cpu.set_irq(1);
                        }
                        self.frame_tick = 0;
                    }
                },
                // step 5
                37287 => self.frame_tick = 0,
                else => {},
            }
        }
    };
}
