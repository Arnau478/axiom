const Token = @This();

const std = @import("std");

type: Type,

pub const Type = union(enum) {
    doctype: Doctype,
    start_tag: Tag,
    end_tag: Tag,
    comment: Span,
    character: Span,

    pub const Doctype = struct {
        name: ?Span = null,
        public: ?Span = null,
        system: ?Span = null,
        force_quirks: bool = false,
    };

    pub const Tag = struct {
        name: Span,
        self_closing: bool = false,
        attributes: Span = .empty,

        pub const Attribute = struct {
            name: Span,
            value: ?Span,

            pub const Iterator = struct {
                rem: Span,

                fn skipCodepoint(iter: *Iterator, source: []const u8) void {
                    iter.rem.start += std.unicode.utf8ByteSequenceLength(iter.rem.slice(source)[0]) catch unreachable;
                }

                fn skipWhitespace(iter: *Iterator, source: []const u8) void {
                    while (iter.rem.slice(source).len > 0 and switch (iter.rem.slice(source)[0]) {
                        '\t', '\n', 0x0C, ' ' => true,
                        else => false,
                    }) {
                        iter.skipCodepoint(source);
                    }
                }

                pub fn next(iter: *Iterator, source: []const u8) ?Attribute {
                    iter.skipWhitespace(source);

                    if (iter.rem.slice(source).len == 0) return null;

                    const name_start = iter.rem.start;
                    while (iter.rem.slice(source).len > 0 and switch (iter.rem.slice(source)[0]) {
                        '\t', '\n', 0x0C, ' ', '=' => false,
                        else => true,
                    }) {
                        iter.skipCodepoint(source);
                    }
                    const name_end = iter.rem.start;

                    if (name_start == name_end) return null;

                    iter.skipWhitespace(source);

                    if (iter.rem.slice(source).len == 0 or iter.rem.slice(source)[0] != '=') {
                        return .{
                            .name = .{ .start = name_start, .end = name_end },
                            .value = null,
                        };
                    }

                    iter.skipCodepoint(source);

                    iter.skipWhitespace(source);

                    if (iter.rem.slice(source).len == 0) {
                        return .{
                            .name = .{ .start = name_start, .end = name_end },
                            .value = .empty,
                        };
                    }

                    const first_value_byte = iter.rem.slice(source)[0];

                    if (first_value_byte == '"' or first_value_byte == '\'') {
                        const quote_char = first_value_byte;
                        iter.skipCodepoint(source);

                        const value_start = iter.rem.start;

                        while (iter.rem.slice(source).len > 0 and iter.rem.slice(source)[0] != quote_char) {
                            iter.skipCodepoint(source);
                        }

                        const value_end = iter.rem.start;

                        if (iter.rem.slice(source).len > 0) {
                            iter.skipCodepoint(source);
                        }

                        return .{
                            .name = .{ .start = name_start, .end = name_end },
                            .value = .{ .start = value_start, .end = value_end },
                        };
                    } else {
                        const value_start = iter.rem.start;
                        while (iter.rem.slice(source).len > 0 and switch (iter.rem.slice(source)[0]) {
                            '\t', '\n', 0x0C, ' ' => false,
                            else => true,
                        }) {
                            iter.skipCodepoint(source);
                        }
                        const value_end = iter.rem.end;

                        return .{
                            .name = .{ .start = name_start, .end = name_end },
                            .value = .{ .start = value_start, .end = value_end },
                        };
                    }
                }
            };
        };

        pub fn attributeIterator(tag: Tag) Attribute.Iterator {
            return .{ .rem = tag.attributes };
        }
    };
};

pub const Span = struct {
    start: usize,
    end: usize,

    pub const empty: Span = .{ .start = 0, .end = 0 };

    pub fn slice(span: Span, source: []const u8) []const u8 {
        return source[span.start..span.end];
    }
};
