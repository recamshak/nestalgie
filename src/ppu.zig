const std = @import("std");

const PPUCTRL = packed struct {
    base_nametable_address: u2,
    vram_address_increment: u1,
    sprite_pattern_table_address: u1,
    background_pattern_table_address: u1,
    sprite_size: u1,
    ppu_master_slave: u1,
    vblank_nmi_enabled: u1,
};

const PPUMASK = packed struct {
    greyscale: u1,
    show_background_in_leftmost_8_pixels: u1,
    show_sprite_in_leftmost_8_pixels: u1,
    enable_backgroud_rendering: u1,
    enable_sprite_rendering: u1,
    emphasize_red: u1,
    emphasize_green: u1,
    emphasize_blue: u1,
};

const PPUSTATUS = packed struct {
    ppu_open_bus: u5,
    sprite_overflow: u1,
    sprite_0_hit: u1,
    vblank: u1,
};

const OAMADDR = u8;

pub const PPU = struct {
    v: u15 = 0,
    t: u15 = 0,
    x: u3 = 0,
    w: u1 = 0,

    draw: *const fn (y: u8, scanline: [320]u8) void,

    pub inline fn read_u8(_: *PPU, address: u16) u8 {
        std.log.info("PPU reading {X:04}\n", .{address});
        return 0;
    }
    pub inline fn write_u8(_: *PPU, address: u16, value: u8) void {
        std.log.info("PPU writing {X:02} @{X:04}\n", .{ value, address });
    }
};
