const std = @import("std");
const tracy = @import("tracy");

const nestalgie = @import("nestalgie");
const Display = @import("./display.zig");
const Audio = @import("./audio.zig");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

var buffer: [128 * 1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
var allocator = fba.allocator();
var display = Display{};
var audio: Audio = undefined;
var keyboard_state: [*c]const bool = undefined;
pub const log_level: std.log.Level = .err;

pub fn main() !void {
    tracy.setThreadName("Main");

    display = try Display.init();
    defer display.deinit();
    keyboard_state = c.SDL_GetKeyboardState(0);

    audio = try Audio.init();

    const draw = struct {
        fn call(y: u8, scanline: [256]u32) void {
            display.draw(y, scanline);
        }
    }.call;

    const sampleHandler = struct {
        fn call(sample: u8) void {
            audio.queueSample(sample);
        }
    }.call;
    const fetchController1 = struct {
        fn call() nestalgie.Controller.Status {
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

    var ines = try nestalgie.INes.parse(data);
    const cartridge = try nestalgie.Cartridge.from_ines(allocator, &ines);
    var nes = try nestalgie.Nes.Nes(u32).create(
        allocator,
        draw,
        sampleHandler,
        display.palette,
        fetchController1,
        cartridge,
    );
    defer nes.deinit();

    var running = true;
    while (running) {
        nes.run_one_frame();
        display.render() catch unreachable;
        tracy.frameMark();

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    running = false;
                },
                c.SDL_EVENT_KEY_UP => {
                    if (event.key.scancode == c.SDL_SCANCODE_Y) {
                        var filename_buffer: [64]u8 = undefined;
                        var tv: std.posix.timeval = undefined;
                        std.posix.gettimeofday(&tv, null);
                        const filename = try std.fmt.bufPrintZ(&filename_buffer, "screenshot-{}.{d:0>6}.bmp", .{ tv.sec, @as(u32, @intCast(tv.usec)) });
                        const s = c.SDL_CreateSurfaceFrom(256, 240, c.SDL_PIXELFORMAT_XBGR8888, &display.frame_buffer, 256 * 4);
                        _ = c.SDL_SaveBMP(s, filename);
                    }
                },
                else => {},
            }
        }
    }
}
