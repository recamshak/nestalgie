const std = @import("std");
const Cartridge = @import("./cartridge.zig").Cartridge;
const CPU = @import("./cpu.zig");
const PPU = @import("./ppu.zig").PPU;
const APU = @import("./apu.zig").APU;
const Controller = @import("./controller.zig");
const tracy = @import("tracy");

const Self = @This();
const Cpu = CPU.Nes6502(Self);

allocator: std.mem.Allocator,
cpu: Cpu,
ppu: PPU(Self, Cpu),
apu: APU,
controller: Controller,
cartridge: Cartridge,

internal_ram: [2048]u8 = .{0} ** 2048,
palette: [32]u8 = .{0} ** 32,

fn map_palette_address(address: u16) u16 {
    if (address & 0x0003 != 0) {
        return address & 0x001F; // Mirroring of $3F00-$3F1F in $3F00-$3FFF
    }
    return address & 0x000F; // $3F1{0,4,8,C} are mirrors of $3F0{0,4,8,C}
}
pub inline fn read_u8(self: *Self, address: u16) u8 {
    return switch (address & 0xE000) {
        0x0000 => self.internal_ram[address & 0x07FF],
        0x2000 => self.ppu.read_u8(address),
        0x4000 => switch (address) {
            0x4016 => self.controller.readController1(),
            0x4017 => self.controller.readController2(),
            else => self.apu.read_u8(address),
        },
        else => self.cartridge.read_u8(address),
    };
}

pub inline fn write_u8(self: *Self, address: u16, value: u8) void {
    switch (address & 0xE000) {
        0x0000 => self.internal_ram[address & 0x07FF] = value,
        0x2000 => self.ppu.write_u8(address, value),
        0x4000 => switch (address) {
            0x4000 => self.apu.write_pulse1_ctrl(@bitCast(value)),
            0x4001 => self.apu.write_pulse1_sweep(@bitCast(value)),
            0x4002 => self.apu.write_pulse1_timer_lo(value),
            0x4003 => self.apu.write_pulse1_timer_hi(value),
            0x4004 => self.apu.write_pulse2_ctrl(@bitCast(value)),
            0x4005 => self.apu.write_pulse2_sweep(@bitCast(value)),
            0x4006 => self.apu.write_pulse2_timer_lo(value),
            0x4007 => self.apu.write_pulse2_timer_hi(value),
            0x4014 => {
                // move that into PPU and use a pointer since it's from a single page and the CPU is "stopped".
                for (0..256) |i| {
                    const data = self.read_u8(@as(u16, value) << 8 | @as(u16, @truncate(i)));
                    self.write_u8(0x2004, data);
                    for (0..6) |_| {
                        self.ppu.tick();
                    }
                }
            },
            0x4016 => self.controller.write(value),
            else => self.apu.write_u8(address, value),
        },
        else => self.cartridge.write_u8(address, value),
    }
}

pub inline fn ppu_read_u8(self: *Self, address: u16) u8 {
    return switch (address & 0xFF00) {
        0x3F00 => self.palette[map_palette_address(address)],
        else => self.cartridge.ppu_read_u8(address),
    };
}

pub inline fn ppu_write_u8(self: *Self, address: u16, value: u8) void {
    switch (address & 0xFF00) {
        0x3F00 => self.palette[map_palette_address(address)] = value,
        else => self.cartridge.ppu_write_u8(address, value),
    }
}

pub fn create(
    allocator: std.mem.Allocator,
    draw: *const fn (y: u8, scanline: [256]u6) void,
    fetch_controller1: *const fn () Controller.Status,
    cartridge: Cartridge,
) !*Self {
    var nes = try allocator.create(Self);
    nes.* = .{
        .cpu = Cpu{ .bus = nes },
        .ppu = PPU(Self, Cpu){
            .cpu = &nes.cpu,
            .draw = draw,
            .bus = nes,
        },
        .apu = APU{},
        .controller = .{ .fetch = fetch_controller1 },
        .cartridge = cartridge,
        .allocator = allocator,
    };
    const pc_lo = @as(u16, nes.read_u8(0xfffc));
    const pc_hi = @as(u16, nes.read_u8(0xfffd));
    nes.cpu.pc = (pc_hi << 8) | pc_lo;
    return nes;
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}

pub fn tick(self: *Self) u8 {
    const zone = tracy.initZone(@src(), .{ .name = "NES tick" });
    defer zone.deinit();

    const cpu_cycles = self.cpu.execute_next_op();
    for (0..cpu_cycles * 3) |_| {
        self.ppu.tick();
    }
    return cpu_cycles;
}
