const std = @import("std");

const PPUCTRL = packed struct {
    base_nametable_address: u2 = 0,
    vram_address_increment: u1 = 0,
    sprite_pattern_table_address: u1 = 0,
    background_pattern_table_address: u1 = 0,
    sprite_size: u1 = 0,
    ppu_master_slave: u1 = 0,
    vblank_nmi_enabled: u1 = 0,
};

const PPUMASK = packed struct {
    greyscale: u1 = 0,
    show_background_in_leftmost_8_pixels: u1 = 0,
    show_sprite_in_leftmost_8_pixels: u1 = 0,
    enable_backgroud_rendering: u1 = 0,
    enable_sprite_rendering: u1 = 0,
    emphasize_red: u1 = 0,
    emphasize_green: u1 = 0,
    emphasize_blue: u1 = 0,
};

const PPUSTATUS = packed struct {
    ppu_open_bus: u5 = 0,
    sprite_overflow: u1 = 0,
    sprite_0_hit: u1 = 0,
    vblank: u1 = 0,
};

const PPUSCROLL = packed struct(u8) {
    fine_scroll: u3,
    coarse_scroll: u5,
};

const Sprite = packed struct {
    y: u8 = 0,
    tile: Tile = .{},
    attribue: Attribute = .{},
    x: u8 = 0,

    const Tile = packed struct {
        bank: u1 = 0,
        tile_number: u7 = 0,
    };

    const Attribute = packed struct {
        palette: u2 = 0,
        _padding: u3 = 0,
        priority: u1 = 0,
        flip_horizontally: u1 = 0,
        flip_vertically: u1 = 0,
    };
};

const PPUADDR = packed struct(u16) {
    lo: u8 = 0,
    hi: u8 = 0,
};

const VRAMADDR = packed struct(u16) {
    coarse_x_scroll: u5 = 0,
    coarse_y_scroll: u5 = 0,
    nametable: u2 = 0,
    fine_y_scroll: u3 = 0,
    _pad: u1 = 0,

    inline fn asWord(self: VRAMADDR) u16 {
        return @bitCast(self);
    }
    inline fn setHighByte(self: *VRAMADDR, value: u8) void {
        self.* = @bitCast((@as(u16, @bitCast(self.*)) & 0x00FF) | (@as(u16, value) << 8));
    }
    inline fn setLowByte(self: *VRAMADDR, value: u8) void {
        self.* = @bitCast((@as(u16, @bitCast(self.*)) & 0xFF00) | value);
    }
};

fn RingBuffer(comptime capacity: u8, Type: type) type {
    const Self = @This();

    return struct {
        buffer: [capacity]Type = undefined,
        head: u8 = 0,
        len: u8 = 0,

        pub fn push(self: *Self, value: Type) void {
            self.buffer[self.head + self.len % capacity] = value;
            if (self.len < capacity) {
                self.len += 1;
            }
        }
        pub fn pop(self: *Self) Type {
            std.debug.assert(self.len > 0);
            const value = self.buffer[self.head];
            self.head = (self.head + 1) % capacity;
            self.len -= 1;
            return value;
        }
        pub fn peek(self: *Self) Type {
            std.debug.assert(self.len > 0);
            return self.buffer[self.head];
        }
    };
}

// The NES has a 2Kb VRAM that can be rerouted by the cartridge as is the
// case for the entire PPU bus address space from 0x0000 to 0x3EFF.
// For simplicity only the non-reroutable address space (0x3F00 - 0x3FFF) is handled by this PPU
// the remaining must be handled by the cartridge.
pub fn PPU(comptime Bus: type) type {
    return struct {
        const Self = @This();

        v: VRAMADDR = .{},
        t: VRAMADDR = .{},
        x: u3 = 0,
        w: u1 = 0,

        ctrl: PPUCTRL = .{},
        mask: PPUMASK = .{},
        status: PPUSTATUS = .{},
        oamaddr: u8 = 0,

        oam: [256]Sprite = .{Sprite{}} ** 256,
        oam_buffer: [8]Sprite = undefined,

        latch: u8 = 0,
        ppudata_read_latch: u8 = 0,

        scanline: u16 = 261,
        scanline_cycle: u16 = 0,
        frame_counter: u8 = 0,

        tile_buffer: RingBuffer(3, u8) = .{},
        attr_buffer: RingBuffer(3, u8) = .{},
        pattern_lsb_buffer: RingBuffer(3, u8) = .{},
        pattern_msb_buffer: RingBuffer(3, u8) = .{},

        pixel_buffer: [320]u8 = .{0} ** 320,
        draw: *const fn (y: u8, pixels: [320]u8) void,

        // All access to PPU bus in the range 0x0000 - 0x3EFF is delegated to this bus
        bus: *Bus,

        inline fn oamBytes(self: *Self) [*]u8 {
            return @ptrCast(&self.oam);
        }

        fn vramAddress(self: *Self) u16 {
            return @bitCast(self.v);
        }

        fn incVramAddress(self: *Self) void {
            const inc: u16 = if (self.ctrl.vram_address_increment == 0) 1 else 32;
            self.v = @bitCast(self.vramAddress() +% inc);
        }

        //fn fetchNextTile(self: *Self) u8 {}

        pub inline fn read_u8(self: *Self, address: u16) u8 {
            std.log.info("PPU reading {X:04}\n", .{address});
            switch (address & 0x0007) {
                2 => {
                    self.latch = @bitCast(self.status);
                    self.w = 0;
                    return self.latch;
                },
                7 => {
                    defer {
                        self.ppudata_read_latch = self.bus.ppu_read_u8(self.vramAddress());
                        self.incVramAddress();
                    }
                    return self.ppudata_read_latch;
                },
                else => return self.latch,
            }
        }
        pub inline fn write_u8(self: *Self, address: u16, value: u8) void {
            std.log.info("PPU writing {X:02} @{X:04}\n", .{ value, address });
            switch (address & 0x0007) {
                // 0x2000 PPUCTRL write
                0 => {
                    self.ctrl = @bitCast(value);
                    self.t.nametable = self.ctrl.base_nametable_address;
                },

                1 => self.mask = @bitCast(value),
                2 => self.latch = value,
                3 => self.oamaddr = value,
                4 => {
                    self.oamBytes()[self.oamaddr] = value;
                    self.oamaddr += 1;
                },
                // 0x2005 PPUSCROLL write
                5 => {
                    const scroll: PPUSCROLL = @bitCast(value);
                    if (self.w == 0) {
                        self.t.coarse_x_scroll = scroll.coarse_scroll;
                        self.x = scroll.fine_scroll;
                    } else {
                        self.t.coarse_y_scroll = scroll.coarse_scroll;
                        self.t.fine_y_scroll = scroll.fine_scroll;
                    }
                    self.w = ~self.w;
                },
                // 0x2006 PPUADDR write
                6 => {
                    if (self.w == 0) {
                        self.t.setHighByte(value & 0x3F);
                    } else {
                        self.t.setLowByte(value);
                        self.v = self.t;
                    }
                    self.w = ~self.w;
                },
                7 => {
                    self.bus.ppu_write_u8(self.v.asWord(), value);
                    self.incVramAddress();
                },
                else => unreachable,
            }
        }

        fn fetch_tile_phase_tick(self: *Self) void {
            switch ((self.scanline_cycle - 1) % 8) {
                // fetch NT
                0 => void,
                // fetch AT
                2 => void,
                // fetch pattern lsb
                4 => void,
                // fetch pattern msb
                6 => void,
                // nothing
                else => void,
            }
        }

        fn fetch_sprite_phase_tick(self: *Self) void {
            switch ((self.scanline_cycle - 1) % 8) {
                // fetch NT
                0 => void,
                // fetch AT
                2 => void,
                // fetch pattern lsb
                4 => void,
                // fetch pattern msb
                6 => void,
                // nothing
                else => void,
            }
        }

        pub fn tick(self: *Self) void {
            switch (self.scanline) {
                // visible scanlines & dummy scanline
                0...239, 261 => {
                    if (self.scanline_cycle == 0) {
                        void;
                    } else if (self.scanline_cycle <= 256) {
                        self.fetch_tile_phase_tick();
                        // TODO: draw pixel
                    } else if (self.scanline_cycle <= 320) {
                        self.fetch_sprite_phase_tick();
                    } else if (self.scanline_cycle <= 336) {
                        self.fetch_tile_phase_tick();
                    } else {
                        // TODO: fetch 2 NT bytes
                    }
                },
                // idle scanline
                240 => void,
                241 => if (self.scanline_cycle == 1) {
                    self.ctrl.vblank_nmi_enabled = 1;
                },
                // VBlank scanlines
                242...260 => void,
            }
            self.scanline_cycle = (self.scanline_cycle + 1) % 341;
            if (self.scanline_cycle == 0) {
                self.scanline = (self.scanline + 1) % 262;
            }
        }
    };
}
