const std = @import("std");

const nestalgie = @import("nestalgie");

const Cartridge = @import("./cartridge.zig").Cartridge;
const NROM = @import("./mapper/nrom.zig").NROM;
const CPU = @import("./cpu.zig");
const PPU = @import("./ppu.zig").PPU;
const APU = @import("./apu.zig").APU;
const Nes = @import("./nes.zig").Nes;
const INes = @import("./ines.zig");

var buffer: [128 * 1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
var allocator = fba.allocator();

pub fn main() !void {
    const filepath = std.mem.span(std.os.argv[1]);
    const stats = try std.fs.cwd().statFile(filepath);
    const data = try allocator.alloc(u8, stats.size);
    _ = try std.fs.cwd().readFile(filepath, data);

    var ines = try INes.parse(data);
    std.log.info("INes: {}", .{ines});
    const cartridge = try Cartridge.from_ines(allocator, &ines);
    var nes = try Nes.create(allocator, cartridge);
    _ = nes.tick();
    _ = nes.tick();
    _ = nes.tick();
    _ = nes.tick();
    _ = nes.tick();
    _ = nes.tick();
}
