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

pub fn next(self: *Tokenizer) ?Token {
    if (self.consume()) |c| {
        switch (c) {
            '\n', '\r', 0xC, '\t', ' ' => {
                self.skipWhitespace();
                return .whitespace;
            },
            '"' => @panic("TODO"),
            '#' => @panic("TODO"),
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
            else => @panic("TODO"),
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
                'A'...'Z', 'a'...'z', '_' => _ = self.consume(),
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
