const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const Self = @This();

pub const DisplayError = error{
    InitError,
    DrawError,
    RenderError,
};

window: ?*c.SDL_Window = undefined,
renderer: ?*c.SDL_Renderer = undefined,
screen_texture: ?*c.SDL_Texture = undefined,
palette: [64]u32 = generate_palette("./2C02G_wiki.pal"),
frame_buffer: [256 * 240]u32 = @splat(0),

fn generate_palette(comptime path: []const u8) [64]u32 {
    var palette: [64]u32 = undefined;
    const rgb24entries = @embedFile(path);

    for (0..64) |i| {
        palette[i] = @as(u32, @intCast(rgb24entries[i * 3])) |
            @as(u32, @intCast(rgb24entries[(i * 3) + 1])) << 8 |
            @as(u32, @intCast(rgb24entries[(i * 3) + 2])) << 16;
    }
    return palette;
}

pub fn init() !Self {
    var display = Self{};
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.log.err("Couldn't initialize SDL: {s}", .{c.SDL_GetError()});
        return DisplayError.InitError;
    }
    if (!c.SDL_CreateWindowAndRenderer("Nestalgie", 1024, 786, c.SDL_WINDOW_RESIZABLE, &display.window, &display.renderer)) {
        std.log.err("Couldn't create window and renderer: {s}", .{c.SDL_GetError()});
        return DisplayError.InitError;
    }
    errdefer c.SDL_DestroyWindow(display.window);
    errdefer c.SDL_DestroyRenderer(display.renderer);
    _ = c.SDL_SetRenderVSync(display.renderer, 1);
    if (!c.SDL_SetRenderLogicalPresentation(display.renderer, 1024, 840, c.SDL_LOGICAL_PRESENTATION_LETTERBOX)) {
        std.log.err("Couldn't setup renderer: {s}", .{c.SDL_GetError()});
        return DisplayError.InitError;
    }
    if (c.SDL_CreateTexture(display.renderer, c.SDL_PIXELFORMAT_XBGR8888, c.SDL_TEXTUREACCESS_STREAMING, 256, 240)) |texture| {
        display.screen_texture = texture;
    } else {
        std.log.err("Couldn't create screen texture: {s}", .{c.SDL_GetError()});
        return DisplayError.InitError;
    }
    _ = c.SDL_SetTextureScaleMode(display.screen_texture, c.SDL_SCALEMODE_NEAREST);
    return display;
}

pub fn deinit(self: *Self) void {
    c.SDL_DestroyTexture(self.screen_texture);
    c.SDL_DestroyRenderer(self.renderer);
    c.SDL_DestroyWindow(self.window);
}

pub fn draw(self: *Self, y: u8, scanline: [256]u6) !void {
    var row = self.frame_buffer[@as(usize, y) * 256 ..];
    for (0..256) |i| {
        row[i] = self.palette[scanline[i]];
    }
}

pub fn render(self: *Self) !void {
    _ = c.SDL_UpdateTexture(self.screen_texture, null, &self.frame_buffer, 4 * 256);
    _ = c.SDL_RenderTexture(self.renderer, self.screen_texture, null, null);
    _ = c.SDL_RenderPresent(self.renderer);
}
