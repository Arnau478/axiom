const std = @import("std");

const Tokenizer = @This();

source: []const u8,
pos: usize = 0,

pub const Span = struct {
    start: usize,
    end: usize,

    pub fn slice(self: Span, data: []const u8) []const u8 {
        return data[self.start..self.end];
    }
};

pub const Token = union(enum) {
    ident: Span,
    function: Span,
    at_keyword: Span,
    hash: struct {
        span: Span,
        type: Type = .unrestricted,

        pub const Type = enum {
            id,
            unrestricted,
        };
    },
    string: Span,
    bad_string,
    url: Span,
    bad_url,
    delim: u8,
    number: Number,
    percentage: f64,
    dimension: Number,
    whitespace,
    cdo,
    cdc,
    colon,
    semicolon,
    comma,
    l_square_bracket,
    r_square_bracket,
    l_paren,
    r_paren,
    l_curly_bracket,
    r_curly_bracket,
    pub const Number = union(enum) {
        number: f64,
        integer: isize,
    };
};

fn consume(self: *Tokenizer) ?u8 {
    defer self.pos += 1;
    return self.peek();
}

fn peek(self: Tokenizer) ?u8 {
    if (self.pos >= self.source.len) return null;
    return self.source[self.pos];
}

fn peekAfterN(self: Tokenizer, n: usize) ?u8 {
    if (self.pos + n >= self.source.len) return null;
    return self.source[self.pos + n];
}

fn reconsume(self: *Tokenizer) void {
    self.pos -= 1;
}

fn skipWhitespace(self: *Tokenizer) void {
    while (true) {
        if (self.peek()) |ws| {
            switch (ws) {
                '\n', '\r', 0xC, '\t', ' ' => _ = self.consume(),
                else => break,
            }
        } else {
            break;
        }
    }
}

fn isValidEscape(chars: [2]u8) bool {
    if (chars[0] != '\\') return false;

    if (chars[1] == '\n') return false;

    return true;
}

fn wouldStartIdentSequence(chars: [3]u8) bool {
    switch (chars[0]) {
        0x2D => {
            switch (chars[1]) {
                'A'...'Z', 'a'...'z', '_', 0x2D => return true,
                else => {
                    if (isValidEscape([_]u8{ chars[1], chars[2] })) {
                        return true;
                    }

                    return false;
                },
            }
        },
        'A'...'Z', 'a'...'z', '_' => return true,
        '\\' => {
            if (isValidEscape([_]u8{ chars[0], chars[1] })) {
                return true;
            }

            return false;
        },
        else => return false,
    }
}

pub fn next(self: *Tokenizer) ?Token {
    if (self.consume()) |c| {
        switch (c) {
            '\n', '\r', 0xC, '\t', ' ' => {
                self.skipWhitespace();
                return .whitespace;
            },
            '"' => @panic("TODO"),
            '#' => {
                const is_hash = is_hash: {
                    if (self.peek()) |char_1| {
                        switch (char_1) {
                            'A'...'Z', 'a'...'z', '_', '0'...'9', '-' => {
                                break :is_hash true;
                            },
                            else => {},
                        }

                        if (self.peekAfterN(1)) |char_2| {
                            if (isValidEscape([_]u8{ char_1, char_2 })) {
                                break :is_hash true;
                            }
                        }
                    }

                    break :is_hash false;
                };

                if (is_hash) {
                    var token = Token{ .hash = .{
                        .span = undefined,
                    } };

                    if (self.peek() != null and
                        self.peekAfterN(1) != null and
                        self.peekAfterN(2) != null and
                        wouldStartIdentSequence([_]u8{
                        self.peek().?,
                        self.peekAfterN(1).?,
                        self.peekAfterN(2).?,
                    })) {
                        token.hash.type = .id;
                    }

                    const start = self.pos;

                    while (true) {
                        if (self.peek()) |ws| {
                            switch (ws) {
                                'A'...'Z', 'a'...'z', '_', '0'...'9', '-' => _ = self.consume(),
                                else => break,
                            }
                        } else {
                            break;
                        }
                    }

                    token.hash.span = .{ .start = start, .end = self.pos };

                    return token;
                } else {
                    @panic("TODO");
                }
            },
            '\'' => @panic("TODO"),
            '(' => @panic("TODO"),
            ')' => @panic("TODO"),
            '+' => @panic("TODO"),
            ',' => @panic("TODO"),
            '-' => @panic("TODO"),
            '.' => @panic("TODO"),
            ':' => return .colon,
            ';' => return .semicolon,
            '<' => @panic("TODO"),
            '@' => @panic("TODO"),
            '[' => @panic("TODO"),
            '\\' => @panic("TODO"),
            ']' => @panic("TODO"),
            '{' => return .l_curly_bracket,
            '}' => return .r_curly_bracket,
            '0'...'9' => @panic("TODO"),
            'A'...'Z', 'a'...'z', '_' => {
                self.reconsume();
                return self.identLikeToken();
            },
            else => return .{ .delim = c },
        }
    } else {
        return null;
    }
}

fn identLikeToken(self: *Tokenizer) Token {
    const start = self.pos;
    while (true) {
        if (self.peek()) |ws| {
            switch (ws) {
                'A'...'Z', 'a'...'z', '_', '0'...'9', '-' => _ = self.consume(),
                else => break,
            }
        } else {
            break;
        }
    }

    const string = self.source[start..self.pos];

    if (std.ascii.eqlIgnoreCase(string, "url") and self.peek() == '(') {
        @panic("TODO");
    } else if (self.peek() == '(') {
        @panic("TODO");
    } else {
        return .{
            .ident = .{
                .start = start,
                .end = start + string.len,
            },
        };
    }
}
