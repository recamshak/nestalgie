const std = @import("std");

const PulseCtrl = packed struct(u8) {
    volume: u4 = 0,
    constant: bool = false,
    repeat: bool = false,
    duty: u2 = 0,
};

const PulseSweep = packed struct(u8) {
    shift: u3 = 0,
    negate: bool = false,
    period: u3 = 0,
    enabled: bool = false,
};

const Pulse = struct {
    ctrl: PulseCtrl = .{},
    sweep: PulseSweep = .{},
    timer: u11 = 0,
    reload: u11 = 0,
};

const LengthAndTimerHi = packed struct(u8) {
    timer_hi: u3,
    length: u5,
};

pub const APU = struct {
    pulse1: Pulse = .{},
    pulse2: Pulse = .{},

    pub fn write_status(_: *APU) void {}
    pub fn read_status(_: *APU) void {}
    pub fn write_frame_counter(_: *APU) void {}

    // 0x4000
    pub fn write_pulse1_ctrl(self: *APU, value: PulseCtrl) void {
        self.pulse1.ctrl = value;
    }
    // 0x4001
    pub fn write_pulse1_sweep(self: *APU, value: PulseSweep) void {
        self.pulse1.sweep = value;
    }
    // 0x4002
    pub fn write_pulse1_timer_lo(self: *APU, value: u8) void {
        self.pulse1.reload = self.pulse1.reload & 0x700 | value;
    }
    // 0x4003
    pub fn write_pulse1_timer_hi(self: *APU, value: u8) void {
        self.pulse1.reload = self.pulse1.reload & 0x0FF | @as(u11, value & 0x07) << 8;
    }

    // 0x4004
    pub fn write_pulse2_ctrl(self: *APU, value: PulseCtrl) void {
        self.pulse2.ctrl = value;
    }
    // 0x4005
    pub fn write_pulse2_sweep(self: *APU, value: PulseSweep) void {
        self.pulse2.sweep = value;
    }
    // 0x4006
    pub fn write_pulse2_timer_lo(self: *APU, value: u8) void {
        self.pulse2.reload = self.pulse2.reload & 0x700 | value;
    }
    // 0x4007
    pub fn write_pulse2_timer_hi(self: *APU, value: u8) void {
        self.pulse2.reload = self.pulse2.reload & 0x0FF | @as(u11, value & 0x07) << 8;
    }

    pub fn write_triangle_ctrl(_: *APU) void {}
    pub fn write_triangle_timer_lo(_: *APU) void {}
    pub fn write_triangle_timer_hi(_: *APU) void {}

    pub fn write_noise_ctrl(_: *APU) void {}
    pub fn write_noise_period(_: *APU) void {}
    pub fn write_noise_length(_: *APU) void {}

    pub fn write_dmc_ctrl(_: *APU) void {}
    pub fn write_dmc_load(_: *APU) void {}
    pub fn write_dmc_address(_: *APU) void {}
    pub fn write_dmc_length(_: *APU) void {}

    pub inline fn read_u8(_: *APU, _: u16) u8 {
        return 0;
    }
    pub inline fn write_u8(_: *APU, _: u16, _: u8) void {}
};
