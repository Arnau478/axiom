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
