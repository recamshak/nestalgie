const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub const AudioError = error{
    InitError,
};

const Self = @This();

stream: *c.SDL_AudioStream = undefined,
buffer: [32]u8 = undefined,
buffer_index: usize = 0,
log: std.fs.File = undefined,

pub fn init(self: *Self) !void {
    const audio_specs = c.SDL_AudioSpec{
        .channels = 1,
        .freq = 44100,
        .format = c.SDL_AUDIO_U8,
    };

    self.log = try std.fs.cwd().createFile("audio.log", .{});

    if (!c.SDL_Init(c.SDL_INIT_AUDIO)) {
        std.log.err("Couldn't initialize SDL: {s}", .{c.SDL_GetError()});
        return AudioError.InitError;
    }
    if (c.SDL_OpenAudioDeviceStream(c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &audio_specs, null, null)) |stream| {
        self.stream = stream;
    } else {
        std.log.err("Could not create SDL Audio device: {s}", .{c.SDL_GetError()});
        return AudioError.InitError;
    }

    if (!c.SDL_ResumeAudioStreamDevice(self.stream)) {
        std.log.err("Could not start audio playback: {s}", .{c.SDL_GetError()});
        return AudioError.InitError;
    }
}

pub fn queueSample(self: *Self, sample: u8) void {
    //_ = self.log.write(&[1]u8{sample}) catch unreachable;
    self.buffer[self.buffer_index] = sample;
    self.buffer_index += 1;
    if (self.buffer_index == self.buffer.len) {
        self.flush();
    }
}

pub fn flush(self: *Self) void {
    if (self.buffer_index != 0) {
        _ = self.log.write(self.buffer[0..self.buffer_index]) catch unreachable;
        if (!c.SDL_PutAudioStreamData(self.stream, &self.buffer, @intCast(self.buffer_index))) {
            std.log.err("Could flush audio data: {s}", .{c.SDL_GetError()});
        }
        self.buffer_index = 0;
    }
}

pub fn clear(self: *Self) void {
    _ = c.SDL_ClearAudioStream(self.stream);
}
