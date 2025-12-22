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

const EvaluatedSprite = struct {
    x: u8,
    priority: u1,
    palette: u2,
    pattern_lsb: u8,
    pattern_msb: u8,
    is_sprite_0: bool,
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
    return struct {
        const Self = @This();
        buffer: [capacity]Type = undefined,
        head_index: u8 = 0,
        len: u8 = 0,

        pub fn append(self: *Self, value: Type) void {
            if (self.len == capacity) {
                self.buffer[self.head_index] = value;
                self.head_index = (self.head_index + 1) % capacity;
            } else {
                self.buffer[(self.head_index + self.len) % capacity] = value;
                self.len += 1;
            }
        }
        pub fn pop_head(self: *Self) Type {
            if (self.len == 0) return 0;
            const value = self.buffer[self.head_index];
            self.head_index = (self.head_index + 1) % capacity;
            self.len -= 1;
            return value;
        }
        pub fn head(self: *Self) Type {
            if (self.len == 0) return 0;
            return self.buffer[self.head_index];
        }
        pub fn tail(self: *Self) Type {
            if (self.len == 0) return 0;
            return self.buffer[self.head_index + self.len - 1];
        }
    };
}

const RenderingContext = struct {
    next_tile_pattern_lsb: u8 = 0,
    next_tile_pattern_msb: u8 = 0,
    next_tile_palette_lsb: u1 = 0,
    next_tile_palette_msb: u1 = 0,

    pattern_lsb: u8 = 0,
    pattern_msb: u8 = 0,
    palette_lsb: u8 = 0, // bit 2
    palette_msb: u8 = 0, // bit 3
};

pub fn PPU(comptime Bus: type, comptime Cpu: type) type {
    return struct {
        const Self = @This();

        v: VRAMADDR = .{},
        t: VRAMADDR = .{},
        x: u3 = 0,
        w: u1 = 0,
        nmi_output: u1 = 0,

        ctrl: PPUCTRL = .{},
        mask: PPUMASK = .{},
        status: PPUSTATUS = .{},
        oamaddr: u8 = 0,

        oam: [256]Sprite = .{Sprite{}} ** 256,
        sprites: [8]EvaluatedSprite = undefined,
        sprites_count: u8 = 0,

        latch: u8 = 0,
        ppudata_read_latch: u8 = 0,

        scanline: u16 = 261,
        dot: u16 = 0,
        is_odd_frame: bool = false,

        pattern_base_address: u16 = 0,

        nametable_buffer: RingBuffer(1, u8) = .{},
        pattern_lsb_buffer: RingBuffer(1, u8) = .{},
        pattern_msb_buffer: RingBuffer(1, u8) = .{},
        palette_lsb_buffer: RingBuffer(1, u1) = .{},
        palette_msb_buffer: RingBuffer(1, u1) = .{},

        pixel_buffer: [256]u6 = .{0} ** 256,
        pixel_buffer_idx: u8 = 0,
        draw: *const fn (y: u8, pixels: [256]u6) void,
        context: RenderingContext = .{},

        bus: *Bus,
        cpu: *Cpu,

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
        fn incCoarseX(self: *Self) void {
            self.v.coarse_x_scroll +%= 1;
            if (self.v.coarse_x_scroll == 0) {
                self.v.nametable ^= 1;
            }
        }
        fn incY(self: *Self) void {
            self.v.fine_y_scroll +%= 1;
            if (self.v.fine_y_scroll == 0) {
                switch (self.v.coarse_y_scroll) {
                    29 => {
                        self.v.coarse_y_scroll = 0;
                        self.v.nametable ^= 2;
                    },
                    31 => self.v.coarse_y_scroll = 0,
                    else => self.v.coarse_y_scroll +%= 1,
                }
            }
        }
        fn tileAddress(self: *Self) u16 {
            return 0x2000 | (self.v.asWord() & 0x0FFF);
        }
        fn attributeAddress(self: *Self) u16 {
            const v = self.v.asWord();
            return 0x23C0 | (v & 0x0C00) | ((v >> 4) & 0x38) | ((v >> 2) & 0x07);
            //return 0x23C0 | (@as(u16, self.v.nametable) << 10) | ((self.v.coarse_y_scroll >> 2) << 3) | (self.v.coarse_x_scroll >> 2);
        }
        fn patternAddress(self: *Self, index: u8, plane: u1) u16 {
            return self.pattern_base_address | @as(u16, index) << 4 | @as(u16, plane) << 3 | self.v.fine_y_scroll;
        }
        fn drawBackground(self: *Self) void {
            const pattern_mask: u8 = @as(u8, 1) << (7 - self.x);
            const pattern_msb: u2 = @intFromBool(self.context.pattern_msb & pattern_mask != 0);
            const pattern_lsb: u2 = @intFromBool(self.context.pattern_lsb & pattern_mask != 0);
            const palette_msb: u4 = @intFromBool(self.context.palette_msb & pattern_mask != 0);
            const palette_lsb: u4 = @intFromBool(self.context.palette_lsb & pattern_mask != 0);

            const color = if (pattern_msb | pattern_lsb == 0)
                self.bus.ppu_read_u8(0x3F00)
            else
                self.bus.ppu_read_u8(@as(u16, 0x3F00) | palette_msb << 3 | palette_lsb << 2 | pattern_msb << 1 | pattern_lsb);

            self.pixel_buffer[self.pixel_buffer_idx] = @truncate(color);
        }
        fn drawSprite(self: *Self) void {
            const x = self.dot - 1;
            for (self.sprites[0..self.sprites_count]) |sprite| {
                if (sprite.x > x or x > sprite.x +| 7) continue;
                const bit: u3 = 7 - @as(u3, @truncate(x - sprite.x));
                const pattern_lsb = (sprite.pattern_lsb >> bit & 1);
                const pattern_msb = (sprite.pattern_msb >> bit & 1);
                if (pattern_msb | pattern_lsb != 0) {
                    const color = self.bus.ppu_read_u8(@as(u16, 0x3F10) | @as(u16, sprite.palette) << 2 | pattern_msb << 1 | pattern_lsb);
                    if (self.pixel_buffer[self.pixel_buffer_idx] & 0x03 != 0 and color & 0x03 != 0 and sprite.is_sprite_0) {
                        self.status.sprite_0_hit = 1;
                    }
                    self.pixel_buffer[self.pixel_buffer_idx] = @truncate(color);
                }
            }
        }
        fn drawNextPixel(self: *Self) void {
            self.drawBackground();
            self.drawSprite();
            self.pixel_buffer_idx +%= 1;
            self.shift_registers();
        }
        fn renderingEnabled(self: *Self) bool {
            return (self.mask.enable_backgroud_rendering | self.mask.enable_sprite_rendering) != 0;
        }

        pub inline fn read_u8(self: *Self, address: u16) u8 {
            switch (address & 0x0007) {
                2 => {
                    self.latch = @as(u8, @bitCast(self.status)) & 0xE0;
                    self.w = 0;
                    self.ctrl.vblank_nmi_enabled = 0;
                    self.cpu.set_nmi(0);
                    return self.latch;
                },
                4 => {
                    if (self.dot <= 64) return 0xFF;
                    self.latch = self.oamBytes()[self.oamaddr];
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
            switch (address & 0x0007) {
                // 0x2000 PPUCTRL write
                0 => {
                    self.ctrl = @bitCast(value);
                    self.pattern_base_address = if (self.ctrl.background_pattern_table_address == 0) 0x0000 else 0x1000;
                    self.t.nametable = self.ctrl.base_nametable_address;
                    self.nmi_output = self.ctrl.vblank_nmi_enabled;
                    if (self.nmi_output == 0 or self.ctrl.vblank_nmi_enabled == 0) self.cpu.set_nmi(0);
                },

                1 => self.mask = @bitCast(value),
                2 => self.latch = value,
                3 => self.oamaddr = value,
                4 => {
                    self.oamBytes()[self.oamaddr] = value;
                    self.oamaddr +%= 1;
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
            switch (self.dot % 8) {
                // fetch NT
                1 => {
                    const val = self.bus.ppu_read_u8(self.tileAddress());
                    self.nametable_buffer.append(val);
                },
                // fetch AT
                3 => {
                    const attribute = self.bus.ppu_read_u8(self.attributeAddress());
                    const attribute_lsb_index: u3 = @truncate((self.v.coarse_y_scroll & 2) << 1 | (self.v.coarse_x_scroll & 2));
                    const mask = @as(u8, 1) << attribute_lsb_index;
                    self.palette_lsb_buffer.append(@bitCast(attribute & mask != 0));
                    self.palette_msb_buffer.append(@bitCast(attribute & (mask << 1) != 0));
                },
                // fetch pattern lsb
                5 => self.pattern_lsb_buffer.append(self.bus.ppu_read_u8(self.patternAddress(
                    self.nametable_buffer.head(),
                    0,
                ))),
                // fetch pattern msb
                7 => self.pattern_msb_buffer.append(self.bus.ppu_read_u8(self.patternAddress(
                    self.nametable_buffer.head(),
                    1,
                ))),
                0 => {
                    _ = self.nametable_buffer.pop_head();
                    self.context.next_tile_pattern_lsb = self.pattern_lsb_buffer.pop_head();
                    self.context.next_tile_pattern_msb = self.pattern_msb_buffer.pop_head();
                    self.context.next_tile_palette_lsb = self.palette_lsb_buffer.pop_head();
                    self.context.next_tile_palette_msb = self.palette_msb_buffer.pop_head();
                    self.incCoarseX();
                },
                else => {},
            }
        }

        fn shift_registers(self: *Self) void {
            self.context.next_tile_pattern_lsb, var bit: u1 = @shlWithOverflow(self.context.next_tile_pattern_lsb, 1);
            self.context.pattern_lsb = (self.context.pattern_lsb << 1) | bit;
            self.context.next_tile_pattern_msb, bit = @shlWithOverflow(self.context.next_tile_pattern_msb, 1);
            self.context.pattern_msb = (self.context.pattern_msb << 1) | bit;
            self.context.palette_lsb = (self.context.palette_lsb << 1) | self.context.next_tile_palette_lsb;
            self.context.palette_msb = (self.context.palette_msb << 1) | self.context.next_tile_palette_msb;
        }

        fn fetch_sprites(self: *Self) void {
            const y: u16 = self.scanline;
            const y_min: u16 = y -| @as(u16, if (self.ctrl.sprite_size == 0) 8 else 16) + 1;

            self.status.sprite_overflow = 0;
            self.sprites_count = 0;
            for (self.oam, 0..) |sprite, idx| {
                if (y_min <= sprite.y and sprite.y <= y) {
                    if (self.sprites_count == 8) {
                        // here we don't reproduce the split overflow bug (https://www.nesdev.org/wiki/PPU_sprite_evaluation#Sprite_overflow_bug)
                        self.status.sprite_overflow = 1;
                        break;
                    } else {
                        self.sprites[self.sprites_count] = self.evaluate_sprite(sprite, idx);
                        self.sprites_count += 1;
                    }
                }
            }
        }

        fn evaluate_sprite(self: *Self, sprite: Sprite, idx: usize) EvaluatedSprite {
            var base_address: u16 = undefined;
            var tile_index: u8 = undefined;
            var sprite_row_number: u8 = undefined;

            switch (self.ctrl.sprite_size) {
                0 => {
                    base_address = 0x1000 * @as(u16, self.ctrl.sprite_pattern_table_address);
                    tile_index = @bitCast(sprite.tile);
                    sprite_row_number = @truncate(switch (sprite.attribue.flip_vertically) {
                        0 => self.scanline - sprite.y,
                        1 => 8 - (self.scanline - sprite.y),
                    });
                },
                1 => {
                    base_address = 0x1000 * @as(u16, sprite.tile.bank);
                    tile_index = @as(u8, @bitCast(sprite.tile)) & 0xFE | @as(u8, if (sprite_row_number >= 8) 1 else 0);
                    sprite_row_number = @truncate(switch (sprite.attribue.flip_vertically) {
                        0 => self.scanline - sprite.y,
                        1 => 16 - (self.scanline - sprite.y),
                    });
                },
            }
            const address = base_address + @as(u16, tile_index) * 16 + sprite_row_number;
            const pattern_lsb = self.bus.ppu_read_u8(address);
            const pattern_msb = self.bus.ppu_read_u8(address + 8);

            return .{
                .x = sprite.x,
                .palette = sprite.attribue.palette,
                .pattern_lsb = if (sprite.attribue.flip_horizontally == 1) @bitReverse(pattern_lsb) else pattern_lsb,
                .pattern_msb = if (sprite.attribue.flip_horizontally == 1) @bitReverse(pattern_msb) else pattern_msb,
                .priority = sprite.attribue.priority,
                .is_sprite_0 = idx == 0,
            };
        }

        pub fn visible_scanline(self: *Self) void {
            if (self.scanline == 0 and self.dot == 0 and self.is_odd_frame) {
                self.dot = 1;
            }
            switch (self.dot) {
                0 => {},
                1...255 => {
                    self.fetch_tile_phase_tick();
                    self.drawNextPixel();
                },
                256 => {
                    self.fetch_tile_phase_tick();
                    self.drawNextPixel();
                    if (self.scanline != 261) {
                        self.draw(@as(u8, self.v.coarse_y_scroll) << 3 | self.v.fine_y_scroll, self.pixel_buffer);
                    }
                    self.incY();
                },
                257 => {
                    self.v.coarse_x_scroll = self.t.coarse_x_scroll;
                    self.v.nametable = (self.v.nametable & 2) | (self.t.nametable & 1);
                },
                258...260 => {},
                // It seems very unlikely that games would deliberately do bank switching between sprites so we do it all in one go.
                // This is done at dot 261 so that MMC3's scanline counter is triggered at the right time.
                261 => if (self.scanline != 261) {
                    self.fetch_sprites();
                },
                262...279 => {},
                280...304 => if (self.scanline == 261) {
                    self.v.coarse_y_scroll = self.t.coarse_y_scroll;
                    self.v.fine_y_scroll = self.t.fine_y_scroll;
                },
                305...320 => {},
                321...336 => {
                    self.fetch_tile_phase_tick();
                    self.shift_registers();
                },
                337...340 => {},
                else => unreachable,
            }
        }

        pub fn tick(self: *Self) void {
            if (self.renderingEnabled() and (self.scanline == 261 or self.scanline <= 239)) {
                self.visible_scanline();
            }

            if (self.dot == 1 and self.scanline == 261) {
                self.ctrl.vblank_nmi_enabled = 0;
                self.status.vblank = 0;
                self.status.sprite_0_hit = 0;
                self.status.sprite_overflow = 0;
                self.cpu.set_nmi(0);
            }
            if (self.dot == 1 and self.scanline == 241) {
                self.ctrl.vblank_nmi_enabled = 1;
                self.status.vblank = 1;
                self.cpu.set_nmi(self.nmi_output);
            }

            self.dot = (self.dot + 1) % 341;
            if (self.dot == 0) {
                self.scanline = (self.scanline + 1) % 262;
                if (self.scanline == 0) {
                    self.is_odd_frame = !self.is_odd_frame;
                }
            }
        }
    };
}
