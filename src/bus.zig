const std = @import("std");
const Cartridge = @import("./cartridge.zig").Cartridge;
const PPU = @import("./ppu.zig").PPU;
const APU = @import("./apu.zig").APU;

const Kb = 1024;
pub const NesBus = struct {
    internal_ram: [2 * Kb]u8 = [_]u8{0} ** (2 * Kb),

    cartridge: Cartridge,
    ppu: PPU,
    apu: APU,

    pub inline fn read_u8(self: *NesBus, address: u16) u8 {
        return switch (address & 0xE000) {
            0x0000 => return self.internal_ram[address & 0x07FF],
            0x2000 => return self.ppu.read_u8(address),
            0x4000 => return self.apu.read_u8(address),
            else => return self.cartridge.read_u8(address),
        };
    }

    pub inline fn write_u8(self: *NesBus, address: u16, value: u8) void {
        switch (address & 0xE000) {
            0x0000 => self.internal_ram[address & 0x07FF] = value,
            0x2000 => self.ppu.write_u8(address, value),
            0x4000 => self.apu.write_u8(address, value),
            else => self.cartridge.write_u8(address, value),
        }
    }
};
