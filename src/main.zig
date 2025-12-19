const std = @import("std");
const tracy = @import("tracy");
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
pub const log_level: std.log.Level = .err;

pub fn main() !void {
    tracy.setThreadName("Main");
    defer tracy.message("Graceful main thread exit", .{});

    display = try Display.init();
    defer display.deinit();
    const draw = struct {
        fn call(y: u8, scanline: [256]u6) void {
            if (y == 0) {
                display.render() catch unreachable;
            }
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

    var running = true;
    while (running) {
        // var key: [1]u8 = undefined;
        //_ = try std.fs.File.stdin().read(&key);
        _ = nes.tick();

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    running = false;
                },
                else => {},
            }
        }
    }
}
