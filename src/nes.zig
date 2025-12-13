const std = @import("std");

const nestalgie = @import("nestalgie");

const Cartridge = @import("./cartridge.zig").Cartridge;
const NROM = @import("./mapper/nrom.zig").NROM;
const CPU = @import("./cpu.zig").Nes6502;
const PPU = @import("./ppu.zig").PPU;
const APU = @import("./apu.zig").APU;
const Bus = @import("./bus.zig").NesBus;

pub const Nes = struct {
    bus: *Bus,
    cpu: CPU(Bus),
    cartridge: Cartridge,
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, cartridge: Cartridge) !Nes {
        var bus: *Bus = try allocator.create(Bus);
        bus.cartridge = cartridge;
        bus.apu = APU{};
        bus.ppu = PPU{};
        var nes = Nes{
            .bus = bus,
            .cpu = CPU(Bus){ .bus = bus },
            .cartridge = cartridge,
            .allocator = allocator,
        };
        nes.init();
        return nes;
    }

    pub fn init(self: *Nes) void {
        const lo = @as(u16, self.bus.read_u8(0xfffc));
        const hi = @as(u16, self.bus.read_u8(0xfffd));
        self.cpu.pc = (hi << 8) | lo;
    }

    pub fn deinit(self: *Nes) void {
        self.allocator.destroy(self.bus);
    }

    pub fn tick(self: *Nes) u8 {
        return self.cpu.execute_next_op();
    }
};
