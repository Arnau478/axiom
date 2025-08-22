const std = @import("std");
const value = @import("value.zig");
const Stylesheet = @import("Stylesheet.zig");

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
            _ = iter.nextCodepoint().?;
            _ = iter.nextCodepoint().?;

            while (iter.peekCodepoint() != null and !std.mem.eql(u8, iter.peekCodepoints(2), "*/")) {
                _ = iter.nextCodepoint().?;
            }

            for (0..2) |_| {
                if (iter.peekCodepoint() != null) {
                    _ = iter.nextCodepoint().?;
                }
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
            ',' => return .{ .type = .comma, .start = start, .end = iter.currentOffset() },
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

const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    token_iter: TokenIterator,
    reconsumed_token: ?Token,

    fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        return .{
            .allocator = allocator,
            .source = source,
            .token_iter = tokenIterator(source),
            .reconsumed_token = null,
        };
    }

    fn consumeToken(parser: *Parser) ?Token {
        if (parser.reconsumed_token) |token| {
            parser.reconsumed_token = null;
            return token;
        } else {
            return parser.token_iter.next();
        }
    }

    fn reconsumeToken(parser: *Parser, token: Token) void {
        std.debug.assert(parser.reconsumed_token == null);
        parser.reconsumed_token = token;
    }

    fn peekToken(parser: *Parser) ?Token {
        var iter = parser.token_iter;
        return iter.next();
    }

    fn declaration(parser: *Parser) !Stylesheet.Rule.Style.Declaration {
        const property_token = parser.consumeToken() orelse return error.SyntaxError;
        if (property_token.type != .ident) return error.SyntaxError;
        if (parser.peekToken() == null or parser.consumeToken().?.type != .colon) return error.SyntaxError;

        var tokens = std.ArrayList(Token).init(parser.allocator);
        defer tokens.deinit();

        while (parser.peekToken() != null and parser.peekToken().?.type != .semicolon and parser.peekToken().?.type != .close_curly) {
            try tokens.append(parser.consumeToken().?);
        }

        if (parser.peekToken() != null and parser.peekToken().?.type == .semicolon) {
            _ = parser.consumeToken().?;
        }

        const property = Stylesheet.Rule.Style.Declaration.Property.byName(property_token.slice(parser.source)) orelse return error.SyntaxError;

        return switch (property) {
            inline else => |p| return @unionInit(
                Stylesheet.Rule.Style.Declaration,
                @tagName(p),
                value.parse(p.Value(), parser.source, tokens.items) orelse return error.SyntaxError,
            ),
        };
    }

    fn declarationList(parser: *Parser) ![]const Stylesheet.Rule.Style.Declaration {
        var declarations = std.ArrayList(Stylesheet.Rule.Style.Declaration).init(parser.allocator);
        defer declarations.deinit();

        while (parser.peekToken() != null and parser.peekToken().?.type != .close_curly) {
            try declarations.append(try parser.declaration());
        }

        return try declarations.toOwnedSlice();
    }

    fn selector(parser: *Parser) !Stylesheet.Rule.Style.Selector {
        // TODO: Proper selectors
        if (parser.peekToken() != null and parser.peekToken().?.type == .ident) {
            return .{
                .simple = .{
                    .tag_name = parser.consumeToken().?.slice(parser.source),
                    .id = null,
                    .class = &.{},
                },
            };
        } else return error.SyntaxError;
    }

    fn rule(parser: *Parser) !Stylesheet.Rule {
        var selectors = std.ArrayList(Stylesheet.Rule.Style.Selector).init(parser.allocator);
        defer selectors.deinit();

        try selectors.append(try parser.selector());
        while (parser.peekToken() != null and parser.peekToken().?.type == .comma) {
            _ = parser.consumeToken().?;
            try selectors.append(try parser.selector());
        }

        if (parser.peekToken() == null or parser.consumeToken().?.type != .open_curly) return error.SyntaxError;

        const declarations = try parser.declarationList();

        if (parser.peekToken() == null or parser.consumeToken().?.type != .close_curly) return error.SyntaxError;

        return .{
            .style = .{
                .selectors = try selectors.toOwnedSlice(),
                .declarations = declarations,
            },
        };
    }

    fn stylesheet(parser: *Parser) !Stylesheet {
        var rules = std.ArrayList(Stylesheet.Rule).init(parser.allocator);
        defer rules.deinit();

        while (parser.peekToken() != null) {
            try rules.append(try parser.rule());
        }

        return .{
            .rules = try rules.toOwnedSlice(),
        };
    }
};

pub fn parseDeclarationList(allocator: std.mem.Allocator, source: []const u8) ![]const Stylesheet.Rule.Style.Declaration {
    var parser = Parser.init(allocator, source);
    return parser.declarationList();
}

pub fn parseStylesheet(allocator: std.mem.Allocator, source: []const u8) !Stylesheet {
    var parser = Parser.init(allocator, source);
    return parser.stylesheet();
}
