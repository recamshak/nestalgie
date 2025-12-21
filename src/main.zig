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
const Controller = @import("controller.zig");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

var buffer: [128 * 1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
var allocator = fba.allocator();
var display = Display{};
var keyboard_state: [*c]const bool = undefined;
pub const log_level: std.log.Level = .err;

pub fn main() !void {
    tracy.setThreadName("Main");

    display = try Display.init();
    defer display.deinit();
    keyboard_state = c.SDL_GetKeyboardState(0);

    const draw = struct {
        fn call(y: u8, scanline: [256]u6) void {
            if (y == 0) {
                display.render() catch unreachable;
                tracy.frameMark();
            }
            display.draw(y, scanline) catch unreachable;
            tracy.frameMarkNamed("scanline");
        }
    }.call;
    const fetchController1 = struct {
        fn call() Controller.Status {
            return .{
                .a = @intFromBool(keyboard_state[c.SDL_SCANCODE_J]),
                .b = @intFromBool(keyboard_state[c.SDL_SCANCODE_K]),
                .up = @intFromBool(keyboard_state[c.SDL_SCANCODE_W]),
                .down = @intFromBool(keyboard_state[c.SDL_SCANCODE_S]),
                .left = @intFromBool(keyboard_state[c.SDL_SCANCODE_A]),
                .right = @intFromBool(keyboard_state[c.SDL_SCANCODE_D]),
                .select = @intFromBool(keyboard_state[c.SDL_SCANCODE_E]),
                .start = @intFromBool(keyboard_state[c.SDL_SCANCODE_Q]),
            };
        }
    }.call;

    const filepath = std.mem.span(std.os.argv[1]);
    const data = try std.fs.cwd().readFileAlloc(allocator, filepath, 64 * 1024);
    defer allocator.free(data);

    var ines = try INes.parse(data);
    const cartridge = try Cartridge.from_ines(allocator, &ines);
    var nes = try Nes.create(
        allocator,
        draw,
        fetchController1,
        cartridge,
    );
    defer nes.deinit();

    var running = true;
    while (running) {
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
