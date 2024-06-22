const std = @import("std");

const Tokenizer = @This();

source: []const u8,
pos: usize = 0,
state: State = .data,
to_reconsume: ?u8 = null,

pub const Span = struct {
    start: usize,
    end: usize,

    pub fn slice(self: Span, data: []const u8) []const u8 {
        return data[self.start..self.end];
    }
};

pub const State = union(enum) {
    data,
    text,
    tag_open: usize,
    end_tag_open: usize,
    tag_name: struct {
        end: bool,
        tag_start: usize,
        name_start: usize,
    },
};

pub const Token = union(enum) {
    text: Span,
    start_tag: struct {
        span: Span,
        raw_name: Span,
    },

    pub const Tag = @typeInfo(Token).Union.tag_type;
};

fn consume(self: *Tokenizer) ?u8 {
    if (self.to_reconsume) |char| {
        self.to_reconsume = null;
        return char;
    }

    defer self.pos += 1;
    return self.peek();
}

fn peek(self: Tokenizer) ?u8 {
    if (self.to_reconsume) |char| {
        return char;
    }

    if (self.pos >= self.source.len) return null;
    return self.source[self.pos];
}

fn reconsume(self: *Tokenizer, char: u8) void {
    std.debug.assert(self.to_reconsume == null);
    self.to_reconsume = char;
}

pub fn scanToken(self: *Tokenizer) ?Token {
    var current_token: ?Token = null;

    while (true) {
        switch (self.state) {
            .data => {
                if (self.consume()) |c| {
                    switch (c) {
                        '&' => @panic("TODO"),
                        '<' => self.state = .{ .tag_open = self.pos - 1 },
                        0 => @panic("TODO"),
                        else => {
                            current_token = .{ .text = .{
                                .start = self.pos - 1,
                                .end = undefined,
                            } };
                            self.state = .text;
                        },
                    }
                } else {
                    return null;
                }
            },
            .text => {
                const done = if (self.peek()) |c|
                    switch (c) {
                        '&', '<', 0 => true,
                        else => false,
                    }
                else
                    true;

                if (done) {
                    self.state = .data;
                    current_token.?.text.end = self.pos;
                    return current_token;
                } else {
                    _ = self.consume();
                }
            },
            .tag_open => |tag_open| {
                if (self.consume()) |c| {
                    switch (c) {
                        '!' => @panic("TODO"),
                        '/' => self.state = .{ .end_tag_open = tag_open },
                        'A'...'Z', 'a'...'z' => {
                            self.reconsume(c);
                            self.state = .{ .tag_name = .{
                                .end = false,
                                .tag_start = tag_open,
                                .name_start = self.pos - 1,
                            } };
                        },
                        '?' => @panic("TODO"),
                        else => @panic("TODO"),
                    }
                } else {
                    @panic("TODO");
                }
            },
            .end_tag_open => |end_tag_open| {
                if (self.consume()) |c| {
                    switch (c) {
                        'A'...'Z', 'a'...'z' => {
                            self.reconsume(c);
                            self.state = .{ .tag_name = .{
                                .end = true,
                                .tag_start = end_tag_open,
                                .name_start = self.pos - 1,
                            } };
                        },
                        '>' => @panic("TODO"),
                        else => @panic("TODO"),
                    }
                } else {
                    @panic("TODO");
                }
            },
            .tag_name => |tag_name| {
                if (self.consume()) |c| {
                    switch (c) {
                        '\t', '\n', 0xC, ' ' => @panic("TODO"),
                        '/' => @panic("TODO"),
                        '>' => {
                            self.state = .data;
                            return .{ .start_tag = .{
                                .span = .{
                                    .start = tag_name.tag_start,
                                    .end = self.pos,
                                },
                                .raw_name = .{
                                    .start = tag_name.name_start,
                                    .end = self.pos - 1,
                                },
                            } };
                        },
                        0 => @panic("TODO"),
                        else => {},
                    }
                } else {
                    @panic("TODO");
                }
            },
        }
    }
}
