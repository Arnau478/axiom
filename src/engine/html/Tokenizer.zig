const Tokenizer = @This();

const std = @import("std");
const Token = @import("Token.zig");

source: []const u8,
idx: usize = 0,
state: State = .data,
last_start_tag_name: ?[]const u8 = null,

const State = union(enum) {
    data,
    rawtext,
    tag_open,
    end_tag_open,
    tag_name: Token,
    rawtext_less_than_sign,
    rawtext_end_tag_open,
    rawtext_end_tag_name: Token.Type.Tag,
    before_attribute_name: Token,
    attribute_name: Token,
    before_attribute_value: Token,
    attribute_value_double_quoted: Token,
    after_attribute_value_quoted: Token,
    markup_declaration_open,
    doctype,
    before_doctype_name,
    doctype_name: Token.Type.Doctype,
    after_doctype_name,
};

fn nextCodepointSlice(tokenizer: Tokenizer) ?[]const u8 {
    if (tokenizer.idx >= tokenizer.source.len) {
        return null;
    }

    const codepoint_len = std.unicode.utf8ByteSequenceLength(tokenizer.source[tokenizer.idx]) catch unreachable;
    return tokenizer.source[tokenizer.idx..][0..codepoint_len];
}

fn consumeCodepoint(tokenizer: *Tokenizer) ?u21 {
    const slice = tokenizer.nextCodepointSlice() orelse return null;
    tokenizer.idx += slice.len;
    return std.unicode.utf8Decode(slice) catch unreachable;
}

fn nextCharacters(tokenizer: Tokenizer, n: usize) []const u8 {
    var t = tokenizer;

    const start = t.idx;
    var end = t.idx;
    for (0..n) |_| {
        end += (t.nextCodepointSlice() orelse break).len;
    }

    return t.source[start..end];
}

fn nextCharactersAre(tokenizer: Tokenizer, str: []const u8) bool {
    return std.mem.eql(u8, tokenizer.nextCharacters(str.len), str);
}

fn nextCharactersAreIgnoreCase(tokenizer: Tokenizer, str: []const u8) bool {
    return std.ascii.eqlIgnoreCase(tokenizer.nextCharacters(str.len), str);
}

fn isAppropriateEndTag(tokenizer: Tokenizer, tag: Token.Type.Tag) bool {
    if (tokenizer.last_start_tag_name) |name| {
        return std.ascii.eqlIgnoreCase(tag.name.slice(tokenizer.source), name);
    } else return false;
}

pub fn next(tokenizer: *Tokenizer) ?Token {
    state: switch (tokenizer.state) {
        .data => {
            const start_pos = tokenizer.idx;
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '&' => @panic("TODO"),
                '<' => continue :state .tag_open,
                0 => @panic("TODO"),
                else => {
                    while (tokenizer.nextCodepointSlice() != null and switch (tokenizer.nextCodepointSlice().?[0]) {
                        '&', '<', 0 => false,
                        else => true,
                    }) {
                        _ = tokenizer.consumeCodepoint().?;
                    }
                    return .{ .type = .{ .character = .{ .start = start_pos, .end = tokenizer.idx } } };
                },
            } else {
                return null;
            }
        },
        .rawtext => {
            const start_pos = tokenizer.idx;
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '<' => continue :state .rawtext_less_than_sign,
                0 => @panic("TODO"),
                else => {
                    while (tokenizer.nextCodepointSlice() != null and switch (tokenizer.nextCodepointSlice().?[0]) {
                        '&', '<', 0 => false,
                        else => true,
                    }) {
                        _ = tokenizer.consumeCodepoint().?;
                    }
                    return .{ .type = .{ .character = .{ .start = start_pos, .end = tokenizer.idx } } };
                },
            } else {
                return null;
            }
        },
        .tag_open => {
            const start_pos = tokenizer.idx;
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '!' => continue :state .markup_declaration_open,
                '/' => continue :state .end_tag_open,
                'A'...'Z', 'a'...'z' => continue :state .{ .tag_name = .{ .type = .{ .start_tag = .{ .name = .{ .start = start_pos, .end = tokenizer.idx } } } } },
                '?' => @panic("TODO"),
                else => @panic("TODO"),
            } else @panic("TODO");
        },
        .end_tag_open => {
            const start_pos = tokenizer.idx;
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                'A'...'Z', 'a'...'z' => continue :state .{ .tag_name = .{ .type = .{ .end_tag = .{ .name = .{ .start = start_pos, .end = tokenizer.idx } } } } },
                '>' => @panic("TODO"),
                else => @panic("TODO"),
            } else @panic("TODO");
        },
        .tag_name => |token| {
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '\t', '\n', 0x0C, ' ' => continue :state .{ .before_attribute_name = token },
                '/' => @panic("TODO"),
                '>' => {
                    tokenizer.state = .data;
                    if (token.type == .start_tag) tokenizer.last_start_tag_name = token.type.start_tag.name.slice(tokenizer.source);
                    return token;
                },
                0 => @panic("TODO"),
                else => {
                    var t = token;
                    switch (t.type) {
                        .start_tag, .end_tag => |*tag| tag.name.end = tokenizer.idx,
                        else => unreachable,
                    }
                    continue :state .{ .tag_name = t };
                },
            } else @panic("TODO");
        },
        .rawtext_less_than_sign => {
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '/' => continue :state .rawtext_end_tag_open,
                else => @panic("TODO"),
            } else @panic("TODO");
        },
        .rawtext_end_tag_open => {
            const start_pos = tokenizer.idx;
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                'A'...'Z', 'a'...'z' => continue :state .{ .rawtext_end_tag_name = .{ .name = .{ .start = start_pos, .end = start_pos } } },
                else => @panic("TODO"),
            } else @panic("TODO");
        },
        .rawtext_end_tag_name => |token| {
            const start_pos = tokenizer.idx;
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '\t', '\n', 0x0C, ' ' => @panic("TODO"),
                '/' => @panic("TODO"),
                '>' => {
                    var t = token;
                    t.name.end = start_pos;
                    if (tokenizer.isAppropriateEndTag(t)) {
                        tokenizer.state = .data;
                        return .{ .type = .{ .end_tag = t } };
                    } else @panic("TODO");
                },
                'A'...'Z', 'a'...'z' => continue :state .{ .rawtext_end_tag_name = token },
                else => @panic("TODO"),
            } else @panic("TODO");
        },
        .before_attribute_name => |token| {
            const start_pos = tokenizer.idx;
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '\t', '\n', 0x0C, ' ' => continue :state .{ .before_attribute_name = token },
                '/', '>' => @panic("TODO"),
                '=' => @panic("TODO"),
                else => {
                    var t = token;
                    t.type.start_tag.attributes = .{ .start = start_pos, .end = tokenizer.idx };
                    continue :state .{ .attribute_name = t };
                },
            } else @panic("TODO");
        },
        .attribute_name => |token| {
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '\t', '\n', 0x0C, ' ', '/', '>' => @panic("TODO"),
                '=' => continue :state .{ .before_attribute_value = token },
                0 => @panic("TODO"),
                '"', '\'', '<' => @panic("TODO"),
                else => continue :state .{ .attribute_name = token },
            } else @panic("TODO");
        },
        .before_attribute_value => |token| {
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '\t', '\n', 0x0C, ' ' => continue :state .{ .before_attribute_value = token },
                '"' => continue :state .{ .attribute_value_double_quoted = token },
                '\'' => @panic("TODO"),
                '>' => @panic("TODO"),
                else => @panic("TODO"),
            } else @panic("TODO");
        },
        .attribute_value_double_quoted => |token| {
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '"' => continue :state .{ .after_attribute_value_quoted = token },
                '&' => @panic("TODO"),
                0 => @panic("TODO"),
                else => continue :state .{ .attribute_value_double_quoted = token },
            } else @panic("TODO");
        },
        .after_attribute_value_quoted => |token| {
            const start_pos = tokenizer.idx;
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '\t', '\n', 0x0C, ' ' => continue :state .{ .before_attribute_name = token },
                '/' => @panic("TODO"),
                '>' => {
                    var t = token;
                    t.type.start_tag.attributes.end = start_pos;
                    tokenizer.state = .data;
                    tokenizer.last_start_tag_name = token.type.start_tag.name.slice(tokenizer.source);
                    return t;
                },
                else => @panic("TODO"),
            } else @panic("TODO");
        },
        .markup_declaration_open => {
            if (tokenizer.nextCharactersAre("--")) {
                @panic("TODO");
            } else if (tokenizer.nextCharactersAreIgnoreCase("DOCTYPE")) {
                for ("DOCTYPE") |_| _ = tokenizer.consumeCodepoint().?;
                continue :state .doctype;
            } else if (tokenizer.nextCharactersAre("[CDATA[")) {
                @panic("TODO");
            } else {
                @panic("TODO");
            }
        },
        .doctype => {
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '\t', '\n', 0x0C, ' ' => continue :state .before_doctype_name,
                '>' => @panic("TODO"),
                else => @panic("TODO"),
            } else @panic("TODO");
        },
        .before_doctype_name => {
            const start_pos = tokenizer.idx;
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '\t', '\n', 0x0C, ' ' => continue :state .before_doctype_name,
                0 => @panic("TODO"),
                '>' => @panic("TODO"),
                else => continue :state .{ .doctype_name = .{ .name = .{ .start = start_pos, .end = tokenizer.idx } } },
            } else @panic("TODO");
        },
        .doctype_name => |doctype| {
            const codepoint = tokenizer.consumeCodepoint();
            if (codepoint) |cp| switch (cp) {
                '\t', '\n', 0x0C, ' ' => continue :state .after_doctype_name,
                '>' => {
                    tokenizer.state = .data;
                    return .{ .type = .{ .doctype = doctype } };
                },
                0 => @panic("TODO"),
                else => {
                    var d = doctype;
                    d.name.?.end = tokenizer.idx;
                    continue :state .{ .doctype_name = d };
                },
            } else @panic("TODO");
        },
        .after_doctype_name => @panic("TODO"),
    }
}

test {
    const source =
        \\<!DOCTYPE html>
        \\<html>
        \\  <head>
        \\    <title>Hello world</title>
        \\  </head>
        \\</html>
    ;

    var tokenizer: Tokenizer = .{ .source = source };

    try std.testing.expectEqualDeep(Token{ .type = .{ .doctype = .{ .name = .{ .start = 10, .end = 14 } } } }, tokenizer.next());
    try std.testing.expectEqualDeep(Token{ .type = .{ .character = .{ .start = 15, .end = 16 } } }, tokenizer.next());
    try std.testing.expectEqualDeep(Token{ .type = .{ .start_tag = .{ .name = .{ .start = 17, .end = 21 } } } }, tokenizer.next());
    try std.testing.expectEqualDeep(Token{ .type = .{ .character = .{ .start = 22, .end = 25 } } }, tokenizer.next());
    try std.testing.expectEqualDeep(Token{ .type = .{ .start_tag = .{ .name = .{ .start = 26, .end = 30 } } } }, tokenizer.next());
    try std.testing.expectEqualDeep(Token{ .type = .{ .character = .{ .start = 31, .end = 36 } } }, tokenizer.next());
    try std.testing.expectEqualDeep(Token{ .type = .{ .start_tag = .{ .name = .{ .start = 37, .end = 42 } } } }, tokenizer.next());
    try std.testing.expectEqualDeep(Token{ .type = .{ .character = .{ .start = 43, .end = 54 } } }, tokenizer.next());
    try std.testing.expectEqualDeep(Token{ .type = .{ .end_tag = .{ .name = .{ .start = 56, .end = 61 } } } }, tokenizer.next());
    try std.testing.expectEqualDeep(Token{ .type = .{ .character = .{ .start = 62, .end = 65 } } }, tokenizer.next());
    try std.testing.expectEqualDeep(Token{ .type = .{ .end_tag = .{ .name = .{ .start = 67, .end = 71 } } } }, tokenizer.next());
    try std.testing.expectEqualDeep(Token{ .type = .{ .character = .{ .start = 72, .end = 73 } } }, tokenizer.next());
    try std.testing.expectEqualDeep(Token{ .type = .{ .end_tag = .{ .name = .{ .start = 75, .end = 79 } } } }, tokenizer.next());
    try std.testing.expectEqual(null, tokenizer.next());
}
