const std = @import("std");
const nestalgie = @import("nestalgie");
const CPU = @import("./cpu.zig");

const NesBus = struct {
    cpuRam: [2048]u8 = [_]u8{0} ** 2048,
    ppu: PPU,

    inline fn read_u8(self: *const NesBus, address: u16) u8 {
        return self.cpuRam[address];
    }
};

const PPU = struct {};

const TestBus = struct {
    data: [2 << 16]u8 = [_]u8{0} ** (2 << 16),

    inline fn read_u8(self: *const TestBus, address: u16) u8 {
        return self.data[address];
    }
};

const nesBus = TestBus{};
inline fn read_u8(address: u16) u8 {
    return nesBus.read_u8(address);
}
inline fn read_u16(address: u16) u16 {
    return (@as(u16, nesBus.read_u8(address)) << 8) + nesBus.read_u8(address + 1);
}

pub fn main() !void {
    var cpu = CPU.Nes6502(read_u8, read_u16){};
    _ = cpu.execute_next_op();
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try nestalgie.bufferedPrint();
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
