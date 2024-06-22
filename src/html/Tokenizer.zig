const std = @import("std");

const Tokenizer = @This();

source: []const u8,
pos: usize = 0,
state: State = .data,

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
    markup_declaration_open: usize,
    doctype: usize,
    before_doctype_name: usize,
    doctype_name,
};

pub const Token = union(enum) {
    text: Span,
    doctype: struct {
        span: Span,
        raw_name: Span,
    },
    start_tag: struct {
        span: Span,
        raw_name: Span,
    },

    pub const Tag = @typeInfo(Token).Union.tag_type;
};

fn consume(self: *Tokenizer) ?u8 {
    defer self.pos += 1;
    return self.peek();
}

fn peek(self: Tokenizer) ?u8 {
    if (self.pos >= self.source.len) return null;
    return self.source[self.pos];
}

fn nextCharsAre(self: Tokenizer, str: []const u8) bool {
    return std.mem.startsWith(u8, self.source[self.pos..], str);
}

fn nextCharsAreIgnoreCase(self: Tokenizer, str: []const u8) bool {
    return std.ascii.startsWithIgnoreCase(self.source[self.pos..], str);
}

fn reconsume(self: *Tokenizer) void {
    self.pos -= 1;
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
                        '!' => self.state = .{ .markup_declaration_open = tag_open },
                        '/' => self.state = .{ .end_tag_open = tag_open },
                        'A'...'Z', 'a'...'z' => {
                            self.reconsume();
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
                            self.reconsume();
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
            .markup_declaration_open => |markup_declaration_open| {
                if (self.nextCharsAre("--")) {
                    @panic("TODO");
                } else if (self.nextCharsAreIgnoreCase("DOCTYPE")) {
                    for (0.."DOCTYPE".len) |_| _ = self.consume();
                    self.state = .{ .doctype = markup_declaration_open };
                } else if (self.nextCharsAre("[CDATA[")) {
                    @panic("TODO");
                } else {
                    @panic("TODO");
                }
            },
            .doctype => |doctype| {
                if (self.consume()) |c| {
                    switch (c) {
                        '\t', '\n', 0xC, ' ' => self.state = .{ .before_doctype_name = doctype },
                        '>' => @panic("TODO"),
                        else => @panic("TODO"),
                    }
                } else {
                    @panic("TODO");
                }
            },
            .before_doctype_name => |before_doctype_name| {
                if (self.consume()) |c| {
                    switch (c) {
                        '\t', '\n', 0xC, ' ' => @panic("TODO"),
                        0 => @panic("TODO"),
                        '>' => @panic("TODO"),
                        else => {
                            current_token = .{ .doctype = .{
                                .span = .{
                                    .start = before_doctype_name,
                                    .end = undefined,
                                },
                                .raw_name = .{
                                    .start = self.pos - 1,
                                    .end = undefined,
                                },
                            } };

                            self.state = .doctype_name;
                        },
                    }
                } else {
                    @panic("TODO");
                }
            },
            .doctype_name => {
                if (self.consume()) |c| {
                    switch (c) {
                        '\t', '\n', 0xC, ' ' => @panic("TODO"),
                        '>' => {
                            self.state = .data;

                            current_token.?.doctype.span.end = self.pos;
                            current_token.?.doctype.raw_name.end = self.pos - 1;

                            return current_token;
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
