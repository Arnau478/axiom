const std = @import("std");

// https://www.w3.org/TR/css-syntax-3

pub const TokenType = enum {
    ident,
    function,
    at_keyword,
    hash,
    string,
    url,
    number,
    dimension,
    percentage,
    cdo,
    cdc,
    delim,
    colon,
    semicolon,
    comma,
    open_square,
    close_square,
    open_paren,
    close_paren,
    open_curly,
    close_curly,
};

pub const Token = struct {
    type: TokenType,
    start: usize,
    end: usize,

    pub fn slice(token: Token, source: []const u8) []const u8 {
        return source[token.start..token.end];
    }
};

pub const TokenIterator = struct {
    codepoint_iter: std.unicode.Utf8Iterator,

    fn nextCodepoint(iter: *TokenIterator) ?u21 {
        return iter.codepoint_iter.nextCodepoint();
    }

    fn peekCodepoint(iter: *TokenIterator) ?u21 {
        const i = iter.codepoint_iter.i;
        defer iter.codepoint_iter.i = i;
        return iter.codepoint_iter.nextCodepoint();
    }

    fn peekCodepoints(iter: *TokenIterator, n: usize) []const u8 {
        return iter.codepoint_iter.peek(n);
    }

    fn currentOffset(iter: *TokenIterator) usize {
        return iter.codepoint_iter.i;
    }

    fn getSource(iter: *TokenIterator) []const u8 {
        return iter.codepoint_iter.bytes;
    }

    fn isIdentStartCodepoint(codepoint: u21) bool {
        return switch (codepoint) {
            'A'...'Z', 'a'...'z', 0x80...std.math.maxInt(u21), '_' => true,
            else => false,
        };
    }

    fn isIdentCodepoint(codepoint: u21) bool {
        return switch (codepoint) {
            '0'...'9', '-' => true,
            else => isIdentStartCodepoint(codepoint),
        };
    }

    fn isWhitespace(codepoint: u21) bool {
        return switch (codepoint) {
            '\n', '\r', '\t', ' ' => true,
            else => false,
        };
    }

    fn wouldStartIdentSequence(slice: []const u8) bool {
        std.debug.assert(std.unicode.utf8CountCodepoints(slice) catch unreachable <= 3);
        var codepoint_iter: std.unicode.Utf8Iterator = .{ .bytes = slice, .i = 0 };

        return switch (codepoint_iter.peek(1)[0]) {
            '-' => isIdentStartCodepoint(std.unicode.utf8Decode(codepoint_iter.peek(2)[1..]) catch return false) or
                codepoint_iter.peek(2)[1] == '-' or
                isValidEscape(codepoint_iter.peek(3)[1..]),
            '\\' => isValidEscape(codepoint_iter.peek(2)),
            else => |codepoint| isIdentStartCodepoint(codepoint),
        };
    }

    fn isValidEscape(slice: []const u8) bool {
        if (slice[0] != '\\') return false;
        if (slice[1] == '\n') return false;
        return true;
    }

    fn skipComments(iter: *TokenIterator) void {
        while (std.mem.eql(u8, iter.peekCodepoints(2), "/*")) {
            const peeked = iter.peekCodepoints(2);
            while (peeked.len > 0 and !std.mem.eql(u8, peeked, "*/")) {
                _ = iter.nextCodepoint().?;
            }
        }
    }

    fn identSequence(iter: *TokenIterator) void {
        while (iter.peekCodepoint()) |codepoint| {
            if (isIdentCodepoint(codepoint)) {
                _ = iter.nextCodepoint().?;
            } else if (isValidEscape(iter.peekCodepoints(2))) {
                _ = iter.nextCodepoint().?;
                @panic("TODO");
            } else {
                break;
            }
        }
    }

    fn identLike(iter: *TokenIterator, start: usize) ?Token {
        iter.identSequence();
        var token: Token = .{
            .type = undefined,
            .start = start,
            .end = iter.currentOffset(),
        };

        const string = token.slice(iter.getSource());

        token.type = type: {
            if (std.ascii.eqlIgnoreCase(string, "url") and iter.peekCodepoint() == '(') {
                _ = iter.nextCodepoint().?;

                while (isWhitespace(iter.peekCodepoints(2)[0]) and isWhitespace(iter.peekCodepoints(2)[1])) {
                    _ = iter.nextCodepoint().?;
                }

                if (iter.peekCodepoints(1)[0] == '"' or
                    iter.peekCodepoints(1)[0] == '\'' or
                    (isWhitespace(iter.peekCodepoints(2)[0]) and
                        (iter.peekCodepoints(2)[1] == '"' or iter.peekCodepoints(2)[1] == '\'')))
                {
                    break :type .function;
                } else {
                    @panic("TODO");
                }
            } else if (iter.peekCodepoint() == '(') {
                _ = iter.nextCodepoint().?;
                break :type .function;
            } else {
                break :type .ident;
            }
        };

        return token;
    }

    fn number(iter: *TokenIterator) void {
        if (iter.peekCodepoint() == '+' or iter.peekCodepoint() == '-') {
            _ = iter.nextCodepoint().?;
        }

        while (iter.peekCodepoint() != null and std.ascii.isDigit(iter.peekCodepoints(1)[0])) {
            _ = iter.nextCodepoint().?;
        }

        if (iter.peekCodepoint() == '.' and iter.peekCodepoints(2).len > 1 and std.ascii.isDigit(iter.peekCodepoints(2)[1])) {
            _ = iter.nextCodepoint().?;
            _ = iter.nextCodepoint().?;

            while (std.ascii.isDigit(iter.peekCodepoints(1)[0])) {
                _ = iter.nextCodepoint().?;
            }
        }

        if (iter.peekCodepoint() == 'e' or iter.peekCodepoint() == 'E') {
            @panic("TODO");
        }
    }

    fn numeric(iter: *TokenIterator, start: usize) ?Token {
        iter.number();

        if (wouldStartIdentSequence(iter.peekCodepoints(3))) {
            iter.identSequence();

            return .{
                .type = .dimension,
                .start = start,
                .end = iter.currentOffset(),
            };
        } else if (iter.peekCodepoint() == '%') {
            _ = iter.nextCodepoint().?;

            return .{
                .type = .percentage,
                .start = start,
                .end = iter.currentOffset(),
            };
        } else {
            return .{
                .type = .number,
                .start = start,
                .end = iter.currentOffset(),
            };
        }
    }

    pub fn next(iter: *TokenIterator) ?Token {
        iter.skipComments();

        const start = iter.currentOffset();
        switch (iter.nextCodepoint() orelse return null) {
            '"' => @panic("TODO"),
            '#' => {
                if (iter.peekCodepoint() != null and (isIdentCodepoint(iter.peekCodepoint().?) or isValidEscape(iter.peekCodepoints(2)))) {
                    iter.identSequence();

                    return .{
                        .type = .hash,
                        .start = start,
                        .end = iter.currentOffset(),
                    };
                } else return .{ .type = .delim, .start = start, .end = iter.currentOffset() };
            },
            '\'' => @panic("TODO"),
            '(' => @panic("TODO"),
            ')' => @panic("TODO"),
            '+' => @panic("TODO"),
            ',' => @panic("TODO"),
            '-' => @panic("TODO"),
            '.' => @panic("TODO"),
            ':' => return .{ .type = .colon, .start = start, .end = iter.currentOffset() },
            ';' => return .{ .type = .semicolon, .start = start, .end = iter.currentOffset() },
            '<' => @panic("TODO"),
            '@' => @panic("TODO"),
            '[' => return .{ .type = .open_square, .start = start, .end = iter.currentOffset() },
            '\\' => @panic("TODO"),
            ']' => return .{ .type = .close_square, .start = start, .end = iter.currentOffset() },
            '{' => return .{ .type = .open_curly, .start = start, .end = iter.currentOffset() },
            '}' => return .{ .type = .close_curly, .start = start, .end = iter.currentOffset() },
            '0'...'9' => return iter.numeric(start),
            else => |codepoint| {
                if (isIdentStartCodepoint(codepoint)) {
                    return iter.identLike(start);
                } else if (isWhitespace(codepoint)) {
                    while (iter.peekCodepoint() != null and isWhitespace(iter.peekCodepoint().?)) {
                        _ = iter.nextCodepoint().?;
                    }

                    return iter.next();
                } else {
                    @panic("TODO");
                }
            },
        }
    }
};

pub fn tokenIterator(source: []const u8) TokenIterator {
    return .{
        .codepoint_iter = .{
            .bytes = source,
            .i = 0,
        },
    };
}

test "Basic tokenization" {
    const source =
        \\strong {
        \\  color: red;
        \\}
    ;

    var iter = tokenIterator(source);
    try std.testing.expectEqualDeep(Token{ .type = .ident, .start = 0, .end = 6 }, iter.next().?);
    try std.testing.expectEqualDeep(Token{ .type = .open_curly, .start = 7, .end = 8 }, iter.next().?);
    try std.testing.expectEqualDeep(Token{ .type = .ident, .start = 11, .end = 16 }, iter.next().?);
    try std.testing.expectEqualDeep(Token{ .type = .colon, .start = 16, .end = 17 }, iter.next().?);
    try std.testing.expectEqualDeep(Token{ .type = .ident, .start = 18, .end = 21 }, iter.next().?);
    try std.testing.expectEqualDeep(Token{ .type = .semicolon, .start = 21, .end = 22 }, iter.next().?);
    try std.testing.expectEqualDeep(Token{ .type = .close_curly, .start = 23, .end = 24 }, iter.next().?);
    try std.testing.expectEqual(null, iter.next());
}
