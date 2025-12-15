const std = @import("std");
const Cartridge = @import("./cartridge.zig").Cartridge;
const CPU = @import("./cpu.zig");
const PPU = @import("./ppu.zig").PPU;
const APU = @import("./apu.zig").APU;

const Self = @This();

allocator: std.mem.Allocator,
cpu: CPU.Nes6502(Self),
ppu: PPU,
apu: APU,
cartridge: Cartridge,

internal_ram: [2048]u8 = .{0} ** 2048,

pub inline fn read_u8(self: *Self, address: u16) u8 {
    return switch (address & 0xE000) {
        0x0000 => self.internal_ram[address & 0x07FF],
        0x2000 => self.ppu.read_u8(address),
        0x4000 => self.apu.read_u8(address),
        else => self.cartridge.read_u8(address),
    };
}

pub inline fn write_u8(self: *Self, address: u16, value: u8) void {
    switch (address & 0xE000) {
        0x0000 => self.internal_ram[address & 0x07FF] = value,
        0x2000 => self.ppu.write_u8(address, value),
        0x4000 => self.apu.write_u8(address, value),
        else => self.cartridge.write_u8(address, value),
    }
}

pub fn create(allocator: std.mem.Allocator, draw: *const fn (y: u8, scanline: [320]u8) void, cartridge: Cartridge) !*Self {
    var nes = try allocator.create(Self);
    nes.* = .{
        .cpu = CPU.Nes6502(Self){ .bus = nes },
        .ppu = PPU{ .draw = draw },
        .apu = APU{},
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
    return self.cpu.execute_next_op();
}
