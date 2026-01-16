const std = @import("std");
const log = std.log.scoped(.ines);
const TvSystem = enum(u1) {
    NTSC = 0,
    PAL = 1,
};
const TvSystemExt = enum(u2) {
    NTSC = 0,
    PAL = 1,
    DUAL = 2,
};

const Flags6 = packed struct(u8) {
    nametable_arrangement: u1,
    persistent_memory: u1,
    trainer: u1,
    alternative_nametable_layout: u1,
    mapper_number_lo: u4,
};

const Flags7 = packed struct(u8) {
    vs_unisystem: u1,
    play_choice: u1,
    nes2_format: u2,
    mapper_number_hi: u4,
};

const Flags9 = packed struct(u8) {
    tv_system: u1,
    reserverd: u7,
};
const Flags10 = packed struct(u8) {
    tv_system: u2,
    _pad1: u2,
    prg_ram: u1,
    bus_conflicts: u1,
    _pad2: u2,
};

const Header = packed struct(u128) {
    magic_number: u32,
    prg_rom_size: u8,
    chr_rom_size: u8,
    flags6: Flags6,
    flags7: Flags7,
    prg_ram_size: u8,
    flags9: Flags9,
    flags10: Flags10,
    unused1: u8,
    unused2: u8,
    unused3: u8,
    unused4: u8,
    unused5: u8,
};

pub const INes = struct {
    header: Header,
    prg_rom: []u8,
    chr_rom: []u8,

    pub fn mapper_id(self: *const INes) u8 {
        const lo = @as(u8, self.header.flags6.mapper_number_lo);
        const hi = @as(u8, self.header.flags7.mapper_number_hi);
        return (hi << 4) | lo;
    }
};

pub fn parse(bytes: []u8) !INes {
    const header = std.mem.bytesAsValue(Header, bytes).*;
    log.info("magic number: {X}", .{header.magic_number});
    log.info("prg rom size: {d}", .{header.prg_rom_size});
    log.info("chr rom size: {d}", .{header.chr_rom_size});
    log.info("header size: {d}", .{@sizeOf(Header)});
    const prg_rom_start = @sizeOf(Header);
    const prg_rom_end = prg_rom_start + 16384 * @as(u16, header.prg_rom_size);
    const chr_rom_start = prg_rom_end;
    const chr_rom_end = chr_rom_start + 8192 * @as(u16, header.chr_rom_size);

    return .{
        .header = header,
        .prg_rom = bytes[prg_rom_start..prg_rom_end],
        .chr_rom = bytes[chr_rom_start..chr_rom_end],
    };
}
