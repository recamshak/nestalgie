const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub const AudioError = error{
    InitError,
};

const Self = @This();

stream: *c.SDL_AudioStream = undefined,
buffer: [128]u8 = undefined,
buffer_index: u32 = 0,

pub fn init() AudioError!Self {
    var audio = Self{};
    const audio_specs = c.SDL_AudioSpec{
        .channels = 1,
        .freq = 44100,
        .format = c.SDL_AUDIO_U8,
    };

    if (!c.SDL_Init(c.SDL_INIT_AUDIO)) {
        std.log.err("Couldn't initialize SDL: {s}", .{c.SDL_GetError()});
        return AudioError.InitError;
    }
    if (c.SDL_OpenAudioDeviceStream(c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &audio_specs, null, null)) |stream| {
        audio.stream = stream;
    } else {
        std.log.err("Could not create SDL Audio device: {s}", .{c.SDL_GetError()});
        return AudioError.InitError;
    }

    if (!c.SDL_ResumeAudioStreamDevice(audio.stream)) {
        std.log.err("Could not start audio playback: {s}", .{c.SDL_GetError()});
        return AudioError.InitError;
    }

    return audio;
}

pub fn queueSample(self: *Self, sample: u8) void {
    self.buffer[self.buffer_index] = sample;
    self.buffer_index += 1;
    if (self.buffer_index == self.buffer.len) {
        self.buffer_index = 0;
        if (!c.SDL_PutAudioStreamData(self.stream, &self.buffer, self.buffer.len)) {
            std.log.err("Could not start audio playback: {s}", .{c.SDL_GetError()});
        }
    }
}
