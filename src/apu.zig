const std = @import("std");
const Pulse = @import("./apu/pulse.zig");
const Triangle = @import("./apu/triangle.zig");
const Envelope = @import("./apu/envelope.zig");
const Noise = @import("./apu/noise.zig");

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

pub const SweepPayload = packed struct(u8) {
    shift: u3 = 0,
    negate: bool = false,
    period: u3 = 0,
    enabled: bool = false,
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

const NoiseModeAndPeriodPayload = packed struct(u8) {
    period: u4,
    _padding: u3,
    mode: u1,
};

const NoiseLengthPayload = packed struct(u8) {
    _padding: u3,
    length_index: u5,
};

const NoiseEnveleopPayload = packed struct(u8) {
    envelope: EnvelopePayload,
    _padding: u2,
};

const StatusPayload = packed struct(u8) {
    enable_pulse1: bool = false,
    enable_pulse2: bool = false,
    enable_triangle: bool = false,
    enable_noise: bool = false,
    enable_dmc: bool = false,
    _pad: u1 = 0,
    frame_interrupt: bool = false,
    dmc_interrupt: bool = false,
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
const ticks_between_sample: f32 = (1_789_773.0 / 44_100.0) - 0.06;

pub fn APU(comptime Cpu: type) type {
    return struct {
        const Self = @This();
        sample_count: u32 = 0,
        tick_count: u32 = 0,

        // Stores the number of CPU cycles elapsed in the current sequencer frame.
        // One frame runs for 29'830 or 37'287 CPU cycles for 4-step and 5-step sequence respectively.
        sequence_tick: u16 = 0,

        sequencer_mode: SequencerMode = .FourSteps,
        disable_interrupt: bool = false,
        pulse1: Pulse = .{},
        pulse2: Pulse = .{},
        triangle: Triangle = .{},
        noise: Noise = .{},

        cpu: *Cpu,
        sample_handler: sampleHandler,
        ticks_before_next_sample: f32 = ticks_between_sample / 2.0,

        pub fn read_status(_: *Self) void {}
        pub fn write_frame_counter(_: *Self) void {}
        pub fn newFrame(self: *Self) void {
            self.ticks_before_next_sample = ticks_between_sample / 2.0;
        }

        // 0x4000
        pub fn write_pulse1_ctrl(self: *Self, value: PulseCtrlPayload) void {
            self.pulse1.envelope = if (value.envelope.disabled)
                .{ .constant = value.envelope.period_or_volume }
            else
                .{ .decay = .{
                    .counter = value.envelope.period_or_volume,
                    .period = value.envelope.period_or_volume,
                    .repeat = value.envelope.loop,
                } };
            self.pulse1.length_counter_halt = value.envelope.loop;
            self.pulse1.setDuty(value.duty);
        }
        // 0x4001
        pub fn write_pulse1_sweep(self: *Self, value: SweepPayload) void {
            self.pulse1.sweep = .{
                .enabled = value.enabled,
                .mode = if (value.negate) .ones_complement else .increase,
                .shift = value.shift,
                .period = value.period,
                .counter = value.period,
            };
        }
        // 0x4002
        pub fn write_pulse1_timer_lo(self: *Self, value: u8) void {
            self.pulse1.period = self.pulse1.period & 0x700 | value;
        }
        // 0x4003
        pub fn write_pulse1_timer_hi(self: *Self, value: LengthAndTimerHi) void {
            self.pulse1.period = self.pulse1.period & 0x0FF | @as(u11, value.timer_hi) << 8;
            self.pulse1.length_counter = length_counters[value.length_index];
            self.pulse1.envelope.reset();
        }

        // 0x4004
        pub fn write_pulse2_ctrl(self: *Self, value: PulseCtrlPayload) void {
            self.pulse2.envelope = if (value.envelope.disabled)
                .{ .constant = value.envelope.period_or_volume }
            else
                .{ .decay = .{
                    .counter = value.envelope.period_or_volume,
                    .period = value.envelope.period_or_volume,
                    .repeat = value.envelope.loop,
                } };
            self.pulse2.length_counter_halt = value.envelope.loop;
            self.pulse2.setDuty(value.duty);
        }
        // 0x4005
        pub fn write_pulse2_sweep(self: *Self, value: SweepPayload) void {
            self.pulse2.sweep = .{
                .enabled = value.enabled,
                .mode = if (value.negate) .twos_complement else .increase,
                .shift = value.shift,
                .period = value.period,
                .counter = value.period,
            };
        }
        // 0x4006
        pub fn write_pulse2_timer_lo(self: *Self, value: u8) void {
            self.pulse2.period = self.pulse2.period & 0x700 | value;
        }
        // 0x4007
        pub fn write_pulse2_timer_hi(self: *Self, value: LengthAndTimerHi) void {
            self.pulse2.period = self.pulse2.period & 0x0FF | @as(u11, value.timer_hi) << 8;
            self.pulse2.length_counter = length_counters[value.length_index];
            self.pulse2.envelope.reset();
        }

        // 0x4008
        pub fn write_triangle_ctrl(self: *Self, value: u8) void {
            self.triangle.control_flag = (value & 0x80) != 0;
            self.triangle.linear_counter_reload_value = @truncate(value & 0x7F);
        }
        // 0x400A
        pub fn write_triangle_timer_lo(self: *Self, value: u8) void {
            self.triangle.timer_period = (self.triangle.timer_period & 0x700) | @as(u11, value);
        }
        // 0x400B
        pub fn write_triangle_timer_hi(self: *Self, value: u8) void {
            const timer_high: u11 = @as(u11, value & 0x07) << 8;
            self.triangle.timer_period = (self.triangle.timer_period & 0x0FF) | timer_high;

            if (self.triangle.enabled) {
                const length_index: u5 = @truncate(value >> 3);
                self.triangle.length_counter = length_counters[length_index];
            }

            self.triangle.linear_counter_reload_flag = true;
        }

        // 0x400C
        pub fn write_noise_ctrl(self: *Self, value: NoiseEnveleopPayload) void {
            self.noise.envelope = if (value.envelope.disabled)
                .{ .constant = value.envelope.period_or_volume }
            else
                .{ .decay = .{
                    .counter = value.envelope.period_or_volume,
                    .period = value.envelope.period_or_volume,
                    .repeat = value.envelope.loop,
                } };
        }

        // 0x400E
        pub fn write_noise_period(self: *Self, value: NoiseModeAndPeriodPayload) void {
            self.noise.mode = value.mode;
            self.noise.period = Noise.period_table[value.period];
        }
        // 0x400F
        pub fn write_noise_length(self: *Self, value: NoiseLengthPayload) void {
            if (self.noise.enabled) {
                self.noise.length_counter = length_counters[value.length_index];
            }
            self.noise.envelope.reset();
        }

        pub fn write_dmc_ctrl(_: *Self) void {}
        pub fn write_dmc_load(_: *Self) void {}
        pub fn write_dmc_address(_: *Self) void {}
        pub fn write_dmc_length(_: *Self) void {}

        // 0x4015
        pub fn write_status(self: *Self, value: StatusPayload) void {
            self.pulse1.length_counter_halt = !value.enable_pulse1;
            if (!value.enable_pulse1) self.pulse1.length_counter = 0;
            self.pulse2.length_counter_halt = !value.enable_pulse2;
            if (!value.enable_pulse2) self.pulse2.length_counter = 0;
            self.triangle.setEnabled(value.enable_triangle);
            self.noise.enabled = value.enable_noise;
            if (!value.enable_noise) self.noise.length_counter = 0;
        }

        // 0x4017
        pub fn write_frame_ctrl(self: *Self, value: FrameCtrlPayload) void {
            self.sequencer_mode = value.sequencer_mode;
            self.disable_interrupt = value.disable_frame_interrupt;
        }

        pub fn clock_envelops(self: *Self) void {
            self.pulse1.envelope.tick();
            self.pulse2.envelope.tick();
            self.noise.envelope.tick();
        }

        pub fn clock_all_channels(self: *Self) void {
            self.pulse1.tick();
            self.pulse2.tick();
            self.noise.tick();
        }

        pub fn clock_length_counter_and_sweep_units(self: *Self) void {
            self.pulse1.clockLengthCounter();
            self.pulse2.clockLengthCounter();
            self.pulse1.clockSweep();
            self.pulse2.clockSweep();
            self.triangle.clockLengthCounter();
            self.noise.clockLengthCounter();
        }

        pub fn generate_sample(self: *Self) u8 {
            self.sample_count += 1;
            const square: f32 = @floatFromInt(self.pulse1.getSample() + self.pulse2.getSample());
            const square_output: f32 = if (square == 0.0)
                0.0
            else
                95.88 / ((8128.0 / square) + 100.0);

            const triangle: f32 = @floatFromInt(self.triangle.getSample());
            const noise: f32 = @floatFromInt(self.noise.getSample());
            const dmc: f32 = 0.0;
            const tnd = 159.79 / ((1.0 / ((triangle / 8227.0) + (noise / 12241.0) + (dmc / 22638.0)) + 100.0));
            return @intFromFloat((square_output + tnd) * 255);
        }

        // This needs to be called every CPU cycle.
        pub fn tick(self: *Self) void {
            self.tick_count += 1;
            self.triangle.tick();
            // every 2 ticks, call tick on each channel
            if (self.sequence_tick % 2 == 0) {
                self.clock_all_channels();
            }

            self.ticks_before_next_sample -= 1;
            if (self.ticks_before_next_sample <= 0.0) {
                const sample = self.generate_sample();
                self.sample_handler(sample);
                self.ticks_before_next_sample += ticks_between_sample;
            }

            // every 7457.5 ticks, progress the sequencer
            self.sequence_tick += 1;
            switch (self.sequence_tick) {
                // step 1
                7457 => {
                    self.clock_envelops();
                    self.triangle.clockLinearCounter();
                    if (self.sequencer_mode == .FiveSteps) {
                        self.clock_length_counter_and_sweep_units();
                    }
                },
                // step 2
                14915 => {
                    self.clock_envelops();
                    self.triangle.clockLinearCounter();
                    if (self.sequencer_mode == .FourSteps) {
                        self.clock_length_counter_and_sweep_units();
                    }
                },
                // step 3
                22372 => {
                    self.clock_envelops();
                    self.triangle.clockLinearCounter();
                    if (self.sequencer_mode == .FiveSteps) {
                        self.clock_length_counter_and_sweep_units();
                    }
                },
                // step 4
                29830 => {
                    self.clock_envelops();
                    self.triangle.clockLinearCounter();
                    if (self.sequencer_mode == .FourSteps) {
                        self.clock_length_counter_and_sweep_units();
                        if (!self.disable_interrupt) {
                            self.cpu.set_irq(1);
                        }
                        self.sequence_tick = 0;
                    }
                },
                // step 5
                37287 => self.sequence_tick = 0,
                else => {},
            }
        }
    };
}
