const std = @import("std");

const nestalgie = @import("nestalgie");

const Cartridge = @import("./cartridge.zig").Cartridge;
const NROM = @import("./mapper/nrom.zig").NROM;
const CPU = @import("./cpu.zig");
const PPU = @import("./ppu.zig").PPU;
const APU = @import("./apu.zig").APU;
const Nes = @import("./nes.zig");
const INes = @import("./ines.zig");
const Display = @import("./io/display.zig");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

var buffer: [128 * 1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
var allocator = fba.allocator();
var display = Display{};

pub fn main() !void {
    display = try Display.init();
    defer display.deinit();
    const draw = struct {
        fn call(y: u8, scanline: [320]u8) void {
            display.draw(y, scanline) catch unreachable;
        }
    }.call;

    const filepath = std.mem.span(std.os.argv[1]);
    const stats = try std.fs.cwd().statFile(filepath);
    const data = try allocator.alloc(u8, stats.size);
    _ = try std.fs.cwd().readFile(filepath, data);

    var ines = try INes.parse(data);
    const cartridge = try Cartridge.from_ines(allocator, &ines);
    var nes = try Nes.create(allocator, draw, cartridge);
    defer nes.deinit();

    for (0..64) |value| {
        draw(@intCast(value), .{@as(u8, @intCast(value))} ** 320);
    }
    var running = true;
    while (running) {
        _ = nes.tick();
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            try display.render();
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    running = false;
                },
                else => {},
            }
        }
    }
}
