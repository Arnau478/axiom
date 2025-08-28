const Tokenizer = @This();

const std = @import("std");
const Token = @import("Token.zig");

source: []const u8,
idx: usize = 0,
state: State = .data,

const State = union(enum) {
    data,
    tag_open,
    end_tag_open,
    tag_name: Token,
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
                '\t', '\n', 0x0C, ' ' => @panic("TODO"),
                '/' => @panic("TODO"),
                '>' => {
                    tokenizer.state = .data;
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
