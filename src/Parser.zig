const std = @import("std");
const dom = @import("dom.zig");
const Stylesheet = @import("Stylesheet.zig");

const Parser = @This();

allocator: std.mem.Allocator,
pos: usize,
input: []const u8,

inline fn advance(self: *Parser) void {
    self.pos += 1;
}

inline fn current(self: *Parser) u8 {
    return self.input[self.pos];
}

inline fn peek(self: *Parser) u8 {
    if (self.pos + 1 >= self.input.len) return 0;
    return self.input[self.pos + 1];
}

inline fn consume(self: *Parser, expected: u8) !void {
    if (self.eof() or self.current() != expected) {
        return error.UnexpectedChar;
    } else {
        self.advance();
    }
}

inline fn ws(self: *Parser) void {
    while (!self.eof() and switch (self.current()) {
        0x20, 0x09, 0x0a, 0x0c, 0x0d => true,
        else => false,
    }) self.advance();
}

inline fn match(self: *Parser, expected: u8) bool {
    if (!self.eof() and self.current() == expected) {
        self.advance();
        return true;
    } else {
        return false;
    }
}

inline fn eof(self: *Parser) bool {
    return self.pos >= self.input.len;
}

pub fn parseCss(self: *Parser) !Stylesheet {
    return try self.cssRoot();
}

pub fn cssRoot(self: *Parser) !Stylesheet {
    var rule_arraylist = std.ArrayList(Stylesheet.Rule).init(self.allocator);
    self.ws();
    while (!self.eof() and self.current() != '<') {
        try rule_arraylist.append(try self.cssRule());
        self.ws();
    }
    return .{ .rules = rule_arraylist.items };
}

pub fn cssRule(self: *Parser) !Stylesheet.Rule {
    return .{
        .selectors = try self.cssSelectors(),
        .declarations = try self.cssDeclarations(),
    };
}

pub fn cssSelectors(self: *Parser) ![]Stylesheet.Selector {
    var selectors = std.ArrayList(Stylesheet.Selector).init(self.allocator);
    blk: while (true) {
        try selectors.append(try self.cssSelector());
        self.ws();
        switch (self.current()) {
            ',' => {
                self.advance();
                self.ws();
            },
            '{' => break :blk,
            else => return error.UnexpectedChar,
        }
    }

    std.mem.sort(Stylesheet.Selector, selectors.items, .{}, struct {
        fn f(_: @TypeOf(.{}), sort_self: Stylesheet.Selector, sort_other: Stylesheet.Selector) bool {
            return sort_self.getSpecificity().order(sort_other.getSpecificity()) == .gt;
        }
    }.f);
    return selectors.items;
}

pub fn cssSelector(self: *Parser) !Stylesheet.Selector {
    return .{
        .simple = try self.cssSimpleSelector(),
    };
}

pub fn cssSimpleSelector(self: *Parser) !Stylesheet.Selector.Simple {
    var tag_name: ?[]const u8 = null;
    var id: ?[]const u8 = null;
    var classes = std.ArrayList([]const u8).init(self.allocator);

    while (!self.eof()) {
        switch (self.current()) {
            '#' => {
                self.advance();
                if (id) |_| return error.MultipleIds;
                id = try self.cssIdentifier();
            },
            '.' => {
                self.advance();
                try classes.append(try self.cssIdentifier());
            },
            '*' => self.advance(),
            'a'...'z', 'A'...'Z', '0'...'9' => {
                if (tag_name) |_| return error.MultipleTagNames;
                tag_name = try self.cssIdentifier();
            },
            else => break,
        }
    }

    return .{
        .tag_name = tag_name,
        .id = id,
        .class = classes.items,
    };
}

pub fn cssIdentifier(self: *Parser) ![]const u8 {
    const start_pos = self.pos;
    while (!self.eof() and switch (self.current()) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => true,
        else => false,
    }) self.advance();
    if (start_pos == self.pos) return error.UnexpectedChar;
    return self.input[start_pos..self.pos];
}

pub fn cssDeclarations(self: *Parser) ![]Stylesheet.Declaration {
    var decl_arraylist = std.ArrayList(Stylesheet.Declaration).init(self.allocator);
    self.ws();
    try self.consume('{');
    self.ws();
    while (self.current() != '}') {
        try decl_arraylist.append(try self.cssDeclaration());
        self.ws();
        if (self.current() != '}') {
            try self.consume(';');
            self.ws();
        }
    }
    try self.consume('}');
    return decl_arraylist.items;
}

pub fn cssDeclaration(self: *Parser) !Stylesheet.Declaration {
    const property = try self.cssIdentifier();
    self.ws();
    try self.consume(':');
    self.ws();
    const value = try self.cssValue();

    return .{
        .property = property,
        .value = value,
    };
}

pub fn cssValue(self: *Parser) !Stylesheet.Value {
    switch (self.current()) {
        '#' => return .{ .color = try self.cssColor() },
        '0'...'9' => return .{ .length = try self.cssLength() },
        else => return .{ .keyword = Stylesheet.Value.Keyword.fromStr(try self.cssIdentifier()) },
    }
}

pub fn cssColor(self: *Parser) !Stylesheet.Value.Color {
    var buf: [8]u4 = undefined;
    var slice: []u4 = buf[0..0];

    try self.consume('#');

    while (std.ascii.isHex(self.current()) and slice.len < 8) {
        const digit: u4 = @truncate(std.fmt.charToDigit(self.current(), 16) catch return error.UnexpectedChar);
        self.advance();
        buf[slice.len] = digit;
        slice = buf[0 .. slice.len + 1];
    }

    return switch (slice.len) {
        3 => .{
            .r = (@as(u8, slice[0]) << 4) + slice[0],
            .g = (@as(u8, slice[1]) << 4) + slice[1],
            .b = (@as(u8, slice[2]) << 4) + slice[2],
            .a = 255,
        },
        4 => .{
            .r = (@as(u8, slice[0]) << 4) + slice[0],
            .g = (@as(u8, slice[1]) << 4) + slice[1],
            .b = (@as(u8, slice[2]) << 4) + slice[2],
            .a = (@as(u8, slice[3]) << 4) + slice[3],
        },
        6 => .{
            .r = (@as(u8, slice[0]) << 4) + slice[1],
            .g = (@as(u8, slice[2]) << 4) + slice[3],
            .b = (@as(u8, slice[4]) << 4) + slice[5],
            .a = 255,
        },
        8 => .{
            .r = (@as(u8, slice[0]) << 4) + slice[1],
            .g = (@as(u8, slice[2]) << 4) + slice[3],
            .b = (@as(u8, slice[4]) << 4) + slice[5],
            .a = (@as(u8, slice[6]) << 4) + slice[7],
        },
        0, 1, 2, 5, 7 => return error.InvalidColor,
        else => unreachable,
    };
}

pub fn cssLength(self: *Parser) !Stylesheet.Value.Length {
    return .{
        .magnitude = try self.cssMagnitude(),
        .unit = try self.cssUnit(),
    };
}

pub fn cssMagnitude(self: *Parser) !f64 {
    const start_pos = self.pos;
    while (!self.eof() and switch (self.current()) {
        '0'...'9', '.' => true,
        else => false,
    }) self.advance();
    if (start_pos == self.pos) return error.UnexpectedChar;
    return std.fmt.parseFloat(f64, self.input[start_pos..self.pos]);
}

pub fn cssUnit(self: *Parser) !Stylesheet.Value.Length.Unit {
    const str = try self.cssIdentifier();
    if (std.mem.eql(u8, str, "px")) return .px;

    return error.InvalidUnit;
}

pub fn parseHtml(self: *Parser) !dom.Node {
    return try self.htmlRoot();
}

pub fn htmlRoot(self: *Parser) !dom.Node {
    if (self.eof()) {
        return .{
            .children = &[_]dom.Node{},
            .node_type = .{
                .element = .{
                    .tag_name = "html",
                    .attributes = dom.AttrMap.init(self.allocator),
                },
            },
        };
    } else return try self.htmlNode();
}

pub fn htmlNode(self: *Parser) anyerror!dom.Node {
    if (self.eof()) return error.ExpectedNode;
    return switch (self.current()) {
        '<' => self.htmlElement(),
        else => self.htmlText(),
    };
}

pub fn htmlElement(self: *Parser) !dom.Node {
    try self.consume('<');
    const name = blk: {
        const start_pos = self.pos;
        while (!self.eof() and switch (self.current()) {
            'a'...'z', 'A'...'Z', '0'...'9' => true,
            else => false,
        }) self.advance();
        break :blk self.input[start_pos..self.pos];
    };
    self.ws();

    var attr = dom.AttrMap.init(self.allocator);
    while (switch (self.current()) {
        0x20, 0x09, 0x0a, 0x0c, 0x0d, 0x00, 0x22, 0x27, 0x3e, 0x2f, 0x3d => false,
        else => true,
    }) {
        const key = blk: {
            const start_pos = self.pos;
            while (switch (self.current()) {
                0x20, 0x09, 0x0a, 0x0c, 0x0d, 0x00, 0x22, 0x27, 0x3e, 0x2f, 0x3d => false,
                else => true,
            }) self.advance();
            break :blk self.input[start_pos..self.pos];
        };
        self.ws();
        var value: ?[]const u8 = null;
        if (self.match('=')) {
            // TODO: Support unquoted and single-quoted values
            self.ws();
            try self.consume('"');
            value = blk: {
                const start_pos = self.pos;
                while (switch (self.current()) {
                    '"' => false,
                    else => true,
                }) self.advance();
                break :blk self.input[start_pos..self.pos];
            };
            try self.consume('"');
        }
        self.ws();
        try attr.put(key, value);
    }
    if (self.match('/')) {
        // Self-closing
        try self.consume('>');
        return .{
            .children = &[_]dom.Node{},
            .node_type = .{
                .element = .{
                    .tag_name = name,
                    .attributes = attr,
                },
            },
        };
    }
    try self.consume('>');

    if (std.mem.eql(u8, name, "style")) {
        const css_node = dom.Node{
            .children = &[_]dom.Node{},
            .node_type = .{ .stylesheet = try self.parseCss() },
        };

        try self.consume('<');
        try self.consume('/');
        if (!std.mem.eql(u8, blk: {
            const start_pos = self.pos;
            while (!self.eof() and switch (self.current()) {
                'a'...'z', 'A'...'Z', '0'...'9' => true,
                else => false,
            }) self.advance();
            break :blk self.input[start_pos..self.pos];
        }, "style")) return error.UnmatchedTag;
        try self.consume('>');
        return .{
            .children = blk: {
                var slice = try self.allocator.alloc(dom.Node, 1);
                slice[0] = css_node;
                break :blk slice;
            },
            .node_type = .{
                .element = .{
                    .tag_name = name,
                    .attributes = attr,
                },
            },
        };
    }
    var children_arraylist = std.ArrayList(dom.Node).init(self.allocator);
    defer children_arraylist.deinit();
    self.ws();
    while (self.peek() != '/') {
        try children_arraylist.append(try self.htmlNode());
        self.ws();
    }
    try self.consume('<');
    try self.consume('/');
    if (!std.mem.eql(u8, blk: {
        const start_pos = self.pos;
        while (!self.eof() and switch (self.current()) {
            'a'...'z', 'A'...'Z', '0'...'9' => true,
            else => false,
        }) self.advance();
        break :blk self.input[start_pos..self.pos];
    }, name)) return error.UnmatchedTag;
    try self.consume('>');
    return .{
        .children = try self.allocator.dupe(dom.Node, children_arraylist.items),
        .node_type = .{
            .element = .{
                .tag_name = name,
                .attributes = attr,
            },
        },
    };
}

pub fn htmlText(self: *Parser) !dom.Node {
    const start_pos = self.pos;
    while (!self.eof() and self.current() != '<') self.advance();
    const slice = self.input[start_pos..self.pos];

    return .{
        .children = &[_]dom.Node{},
        .node_type = .{
            .text = slice,
        },
    };
}

pub fn init(allocator: std.mem.Allocator, input: []const u8) Parser {
    return .{
        .allocator = allocator,
        .pos = 0,
        .input = input,
    };
}

pub fn deinit(self: *Parser) void {
    _ = self;
}
