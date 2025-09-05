const Font = @This();

const std = @import("std");

pub const Buffer = @import("Font/Buffer.zig");
pub const Glyph = @import("Font/Glyph.zig");

type: union(enum) {
    ttf: Ttf,
},

pub const Ttf = @import("Font/Ttf.zig");

pub fn parse(allocator: std.mem.Allocator, reader: *std.Io.Reader) !Font {
    return .{ .type = .{ .ttf = try .parse(allocator, reader) } };
}

pub fn deinit(font: Font, allocator: std.mem.Allocator) void {
    switch (font.type) {
        inline else => |f| f.deinit(allocator),
    }
}

pub fn getGlyph(font: Font, allocator: std.mem.Allocator, char: u21) !?Glyph {
    return switch (font.type) {
        inline else => |f| f.getGlyph(allocator, char),
    };
}

pub fn rasterizeCharacter(font: Font, allocator: std.mem.Allocator, char: u21, size: usize) !Buffer {
    const glyph = (try font.getGlyph(allocator, char)).?;
    defer glyph.deinit(allocator);

    const buffer = try Buffer.init(
        allocator,
        @intFromFloat(glyph.bounding_box.width * @as(f32, @floatFromInt(size))),
        @intFromFloat(glyph.bounding_box.height * @as(f32, @floatFromInt(size))),
    );
    errdefer buffer.deinit(allocator);

    glyph.rasterize(buffer, size);

    return buffer;
}
