const Ttf = @This();

const std = @import("std");
const Font = @import("../Font.zig");
const Glyph = @import("Glyph.zig");

const log = std.log.scoped(.ttf);

cmap: ?[]const u8 = null,
glyf: ?[]const u8 = null,
head: ?[]const u8 = null,
loca: ?[]const u8 = null,

const TableDirectory = struct {
    cmap: ?Entry = null,
    glyf: ?Entry = null,
    head: ?Entry = null,
    loca: ?Entry = null,

    const Entry = struct {
        checksum: u32,
        offset: u32,
        length: u32,
    };
};

pub const Header = packed struct(u432) {
    glyph_data_format: i16,
    index_to_loc_format: i16,
    font_direction_hint: i16,
    lowest_rec_ppem: u16,
    mac_style: u16,
    y_max: u16,
    x_max: u16,
    y_min: u16,
    x_min: u16,
    modified: u64,
    created: u64,
    units_per_em: u16,
    flags: u16,
    magic_number: u32,
    checksum_adjustment: u32,
    font_revision: u32,
    version: u32,
};

pub fn parse(allocator: std.mem.Allocator, reader: *std.Io.Reader) !Ttf {
    const scaler_type = try reader.takeInt(u32, .big);
    if (scaler_type != 0x00010000) return error.InvalidTtf;
    const num_tables = try reader.takeInt(u16, .big);
    log.debug("{} tables", .{num_tables});
    try reader.discardAll(6);

    var table_directory: TableDirectory = .{};

    for (0..num_tables) |_| {
        var tag: [4]u8 = undefined;
        try reader.readSliceAll(&tag);

        const entry: TableDirectory.Entry = .{
            .checksum = try reader.takeInt(u32, .big),
            .offset = try reader.takeInt(u32, .big),
            .length = try reader.takeInt(u32, .big),
        };

        switch (@as(u32, @bitCast(tag))) {
            @as(u32, @bitCast(@as([4]u8, "cmap".*))) => table_directory.cmap = entry,
            @as(u32, @bitCast(@as([4]u8, "glyf".*))) => table_directory.glyf = entry,
            @as(u32, @bitCast(@as([4]u8, "head".*))) => table_directory.head = entry,
            @as(u32, @bitCast(@as([4]u8, "loca".*))) => table_directory.loca = entry,
            else => {
                log.debug("Unknown table tag '{s}'", .{@as([4]u8, @bitCast(tag))});
            },
        }
    }

    if (table_directory.cmap == null) return error.InvalidTtf;
    if (table_directory.glyf == null) return error.InvalidTtf;
    if (table_directory.head == null) return error.InvalidTtf;
    if (table_directory.loca == null) return error.InvalidTtf;

    var ttf: Ttf = .{};
    errdefer ttf.deinit(allocator);

    var current_offset: usize = 12 + 16 * num_tables;
    for (0..num_tables) |_| {
        var entry: ?TableDirectory.Entry = null;
        var entry_name: [4]u8 = undefined;
        inline for (comptime std.meta.fieldNames(TableDirectory)) |table_name| {
            if (@field(table_directory, table_name)) |e| {
                if (e.offset < current_offset) comptime continue;
                if (entry == null or entry.?.offset > e.offset) {
                    entry = e;
                    @memcpy(&entry_name, table_name);
                }
            }
        }

        if (entry == null) break;

        log.debug("Reading table '{s}'", .{&entry_name});

        try reader.discardAll(entry.?.offset - current_offset);
        inline for (comptime std.meta.fieldNames(TableDirectory)) |table_name| {
            if (std.mem.eql(u8, table_name, &entry_name)) {
                @field(ttf, table_name) = try reader.readAlloc(allocator, entry.?.length);
            }
        }
        current_offset = @as(usize, entry.?.offset) + @as(usize, entry.?.length);
    }

    if (ttf.cmap == null) return error.InvalidTtf;
    if (ttf.glyf == null) return error.InvalidTtf;
    if (ttf.head == null) return error.InvalidTtf;
    if (ttf.loca == null) return error.InvalidTtf;

    if (ttf.header() == null) return error.InvalidTtf;

    if (ttf.header().?.version != 0x00010000) return error.InvalidTtf;

    if (ttf.header().?.magic_number != 0x5F0F3CF5) return error.InvalidTtf;

    if (ttf.header().?.index_to_loc_format != 0 and ttf.header().?.index_to_loc_format != 1) return error.InvalidTtf;

    log.debug("Units per em: {d}", .{ttf.header().?.units_per_em});
    if (@popCount(ttf.header().?.units_per_em) != 1) log.warn("Units per em is set to {d}, which is not a power of 2", .{ttf.header().?.units_per_em});
    if (ttf.header().?.units_per_em < 64) log.warn("Units per em is set to {d}, which is less than 64", .{ttf.header().?.units_per_em});
    if (ttf.header().?.units_per_em > 16384) log.warn("Units per em is set to {d}, which is greater than 16384", .{ttf.header().?.units_per_em});

    return ttf;
}

pub fn deinit(ttf: Ttf, allocator: std.mem.Allocator) void {
    if (ttf.cmap) |cmap| allocator.free(cmap);
    if (ttf.glyf) |glyf| allocator.free(glyf);
    if (ttf.head) |head| allocator.free(head);
    if (ttf.loca) |loca| allocator.free(loca);
}

pub fn header(ttf: Ttf) ?Header {
    if (ttf.head) |head| {
        if (head.len < @divExact(@bitSizeOf(Header), 8)) return null;
        if (head.len > @divExact(@bitSizeOf(Header), 8)) {
            log.warn("'head' table is too big ({d} bytes, should be {d})", .{ head.len, @divExact(@bitSizeOf(Header), 8) });
        }

        var reader = std.Io.Reader.fixed(head);
        return reader.takeStruct(Header, .big) catch return null;
    } else return null;
}

fn unitsToEm(ttf: Ttf, units: isize) f32 {
    return @as(f32, @floatFromInt(units)) / @as(f32, @floatFromInt(ttf.header().?.units_per_em));
}

fn glyphIndexFromCharacter(ttf: Ttf, char: u21) u32 {
    const number_of_subtables = std.mem.readInt(u16, ttf.cmap.?[2..4], .big);

    var found_table: ?[*]const u8 = null;
    for (0..number_of_subtables) |i| {
        const subtable = ttf.cmap.?[4 + i * 8 ..][0..8];

        const platform = std.mem.readInt(u16, subtable[0..2], .big);
        const platform_specific = std.mem.readInt(u16, subtable[2..4], .big);
        const offset = std.mem.readInt(u32, subtable[4..8], .big);

        if (platform == 0 and platform_specific != 14) {
            found_table = ttf.cmap.?[offset..].ptr;
        }
    }

    if (found_table) |table| {
        const format = std.mem.readInt(u16, table[0..2], .big);
        switch (format) {
            4 => @panic("TODO"),
            12 => {
                const number_of_groups = std.mem.readInt(u32, table[12..16], .big);
                for (0..number_of_groups) |i| {
                    const start_char_code = std.mem.readInt(u32, table[16 + i * 12 ..][0..4], .big);
                    const end_char_code = std.mem.readInt(u32, table[16 + i * 12 ..][4..8], .big);
                    const start_glyph_index = std.mem.readInt(u32, table[16 + i * 12 ..][8..12], .big);

                    if (@as(u32, char) >= start_char_code and @as(u32, char) <= end_char_code) {
                        return start_glyph_index + (@as(u32, char) - start_char_code);
                    }
                }

                return 0;
            },
            else => {
                log.warn("'cmap' format {d} not supported", .{format});
                return 0;
            },
        }
    } else {
        log.warn("No unicode 'cmap' subtable", .{});
        return 0;
    }
}

fn glyphOffsetFromIndex(ttf: Ttf, index: usize) u32 {
    switch (ttf.header().?.index_to_loc_format) {
        0 => {
            const offset = index * 2;
            const bytes = ttf.loca.?[offset .. offset + 2];
            const value = std.mem.readInt(u16, bytes[0..2], .big);
            return @as(u32, value) * 2;
        },
        1 => {
            const offset = index * 4;
            const bytes = ttf.loca.?[offset .. offset + 4];
            return std.mem.readInt(u32, bytes[0..4], .big);
        },
        else => unreachable,
    }
}

fn getGlyphFromOffset(ttf: Ttf, allocator: std.mem.Allocator, glyph_offset: u32) !?Glyph {
    var reader = std.Io.Reader.fixed(ttf.glyf.?[glyph_offset..]);

    const number_of_contours = reader.takeInt(i16, .big) catch return null;
    const x_min = reader.takeInt(i16, .big) catch return null;
    const y_min = reader.takeInt(i16, .big) catch return null;
    const x_max = reader.takeInt(i16, .big) catch return null;
    const y_max = reader.takeInt(i16, .big) catch return null;

    if (number_of_contours >= 0) {
        const end_points_of_contours = try allocator.alloc(u16, @intCast(number_of_contours));
        defer allocator.free(end_points_of_contours);
        for (0..@intCast(number_of_contours)) |i| {
            end_points_of_contours[i] = reader.takeInt(u16, .big) catch return null;
        }

        const number_of_points = if (number_of_contours == 0) 0 else end_points_of_contours[end_points_of_contours.len - 1] + 1;

        const instruction_length = reader.takeInt(u16, .big) catch return null;
        reader.discardAll(instruction_length) catch return null;

        const flags = try allocator.alloc(packed struct(u8) {
            on_curve: bool,
            x_short: bool,
            y_short: bool,
            repeat: bool,
            sign_or_skip_x: bool,
            sign_or_skip_y: bool,
            rsv: u2 = 0,
        }, number_of_points);
        errdefer allocator.free(flags);

        const points = try allocator.alloc(Glyph.Point, number_of_points);
        defer allocator.free(points);

        var repeat_count: usize = 0;
        for (0..number_of_points) |i| {
            if (repeat_count > 0) {
                flags[i] = flags[i - 1];
                repeat_count -= 1;
            } else {
                flags[i] = @bitCast(reader.takeByte() catch return null);
                if (flags[i].repeat) {
                    repeat_count = reader.takeByte() catch return null;
                }
            }
        }

        var last_x: f32 = 0;
        for (0..number_of_points) |i| {
            points[i].x = last_x;
            if (flags[i].x_short) {
                points[i].x += ttf.unitsToEm(@as(i16, reader.takeByte() catch return null) * @as(i16, if (flags[i].sign_or_skip_x) 1 else -1));
            } else {
                if (!flags[i].sign_or_skip_x) {
                    points[i].x += ttf.unitsToEm(reader.takeInt(i16, .big) catch return null);
                }
            }

            last_x = points[i].x;
        }

        var last_y: f32 = 0;
        for (0..number_of_points) |i| {
            points[i].y = last_y;
            if (flags[i].y_short) {
                points[i].y += ttf.unitsToEm(@as(i16, reader.takeByte() catch return null) * @as(i16, if (flags[i].sign_or_skip_y) 1 else -1));
            } else {
                if (!flags[i].sign_or_skip_y) {
                    points[i].y += ttf.unitsToEm(reader.takeInt(i16, .big) catch return null);
                }
            }

            last_y = points[i].y;
        }

        const contours = try allocator.alloc(Glyph.Contour, @intCast(number_of_contours));
        errdefer allocator.free(contours);

        var last_contour_end: usize = 0;
        for (contours, 0..) |*contour, i| {
            contour.* = .{ .points = try allocator.dupe(Glyph.Point, points[last_contour_end..(end_points_of_contours[i] + 1)]) };
            last_contour_end = end_points_of_contours[i] + 1;
        }

        return .{
            .contours = contours,
            .bounding_box = .{
                .x = ttf.unitsToEm(x_min),
                .y = ttf.unitsToEm(y_min),
                .width = ttf.unitsToEm(x_max - x_min),
                .height = ttf.unitsToEm(y_max - y_min),
            },
        };
    } else {
        var contours: std.ArrayList(Glyph.Contour) = .empty;
        errdefer contours.deinit(allocator);

        while (true) {
            const flags = reader.takeStruct(packed struct(u16) {
                arg_1_and_2_are_words: bool,
                args_are_xy_values: bool,
                round_xy_to_grid: bool,
                we_have_a_scale: bool,
                obsolete: u1 = 0,
                more_components: bool,
                we_have_an_x_and_y_scale: bool,
                we_have_a_two_by_two: bool,
                we_have_instructions: bool,
                use_my_metrics: bool,
                overlap_compound: bool,
                padding: u5 = 0,
            }, .big) catch return null;
            const component_index = reader.takeInt(u16, .big) catch return null;

            if (flags.args_are_xy_values) {
                const x_offset = if (flags.arg_1_and_2_are_words) reader.takeInt(i16, .big) catch return null else @as(i16, reader.takeByteSigned() catch return null);
                const y_offset = if (flags.arg_1_and_2_are_words) reader.takeInt(i16, .big) catch return null else @as(i16, reader.takeByteSigned() catch return null);

                const component_offset = ttf.glyphOffsetFromIndex(component_index);
                if (try ttf.getGlyphFromOffset(allocator, component_offset)) |component| {
                    defer component.deinit(allocator);

                    for (component.contours) |contour| {
                        const points = try allocator.dupe(Glyph.Point, contour.points);
                        errdefer allocator.free(points);

                        for (points) |*point| {
                            point.x += ttf.unitsToEm(x_offset);
                            point.y += ttf.unitsToEm(y_offset);
                        }

                        try contours.append(allocator, .{ .points = points });
                    }
                }
            } else @panic("TODO");

            if (!flags.more_components) break;
        }

        return .{
            .contours = try contours.toOwnedSlice(allocator),
            .bounding_box = .{
                .x = ttf.unitsToEm(x_min),
                .y = ttf.unitsToEm(y_min),
                .width = ttf.unitsToEm(x_max - x_min),
                .height = ttf.unitsToEm(y_max - y_min),
            },
        };
    }
}

pub fn getGlyph(ttf: Ttf, allocator: std.mem.Allocator, char: u21) !?Glyph {
    const index = ttf.glyphIndexFromCharacter(char);
    const offset = ttf.glyphOffsetFromIndex(index);
    return try ttf.getGlyphFromOffset(allocator, offset);
}
