const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");
const Stylesheet = @import("Stylesheet.zig");

const Parser = @This();

tokens: []const Tokenizer.Token,
pos: usize,
arena: std.heap.ArenaAllocator,
source: []const u8,

pub fn fromSource(allocator: std.mem.Allocator, source: []const u8) !Parser {
    var arena = std.heap.ArenaAllocator.init(allocator);

    var tokens = std.ArrayList(Tokenizer.Token).init(arena.allocator());
    try tokens.ensureTotalCapacity(@divFloor(source.len, 10)); // TODO: Is this a good value?

    var tokenizer = Tokenizer{
        .source = source,
    };
    while (tokenizer.next()) |token| {
        try tokens.append(token);
    }

    return .{
        .tokens = try tokens.toOwnedSlice(),
        .pos = 0,
        .arena = arena,
        .source = source,
    };
}

pub fn deinit(self: Parser) void {
    self.arena.deinit();
}

fn consumeToken(self: *Parser) ?Tokenizer.Token {
    defer self.pos += 1;
    return self.peekToken();
}

fn peekToken(self: *Parser) ?Tokenizer.Token {
    if (self.pos >= self.tokens.len) return null;
    return self.tokens[self.pos];
}

fn reconsumeToken(self: *Parser) void {
    self.pos -= 1;
}

fn skipWhitespace(self: *Parser) void {
    while (self.peekToken() != null and self.peekToken().? == .whitespace) {
        _ = self.consumeToken();
    }
}

pub fn parseStylesheet(self: *Parser, location: ?[]const u8) !Stylesheet {
    return .{
        .location = location,
        .rules = try self.consumeRuleList(true),
    };
}

pub fn parseRuleList(self: *Parser) ![]const Stylesheet.Rule {
    return try self.consumeRuleList(false);
}

pub fn parseRule(self: *Parser) !Stylesheet.Rule {
    self.skipWhitespace();

    const rule = rule: {
        if (self.peekToken() == null) {
            @panic("TODO");
        } else if (self.peekToken() != null and self.peekToken().? == .at_keyword) {
            @panic("TODO");
        } else {
            if (try self.consumeQualifiedRule()) |rule| {
                break :rule rule;
            } else {
                @panic("TODO");
            }
        }
    };

    self.skipWhitespace();

    if (self.peekToken() == null) {
        return rule;
    } else {
        @panic("TODO");
    }
}

pub fn parseDeclaration(self: *Parser) !Stylesheet.Rule.Declaration {
    self.skipWhitespace();

    if (self.peekToken() == null or self.peekToken().? != .ident) {
        @panic("TODO");
    }

    if (try self.consumeDeclaration()) |decl| {
        return decl;
    } else {
        @panic("TODO");
    }
}

pub fn parseStyleBlockContent(self: *Parser) void {
    return self.consumeStyleBlockContent();
}

pub fn parseDeclarationList(self: *Parser) ![]const Stylesheet.Rule.Declaration {
    return try self.consumeDeclarationList();
}

pub fn parseSelector(self: *Parser) !Stylesheet.Rule.Selector {
    self.skipWhitespace();

    if (self.peekToken() == null) {
        @panic("TODO");
    }

    const value = try self.consumeSelector();

    self.skipWhitespace();

    if (self.peekToken() == null) {
        return value;
    } else {
        @panic("TODO");
    }
}

fn consumeRuleList(self: *Parser, top_level: bool) ![]const Stylesheet.Rule {
    var rules = std.ArrayList(Stylesheet.Rule).init(self.arena.allocator());

    while (true) {
        if (self.consumeToken()) |token| {
            switch (token) {
                .whitespace => {},
                .cdo, .cdc => {
                    if (!top_level) {
                        @panic("TODO");
                    }
                },
                .at_keyword => @panic("TODO"),
                else => {
                    self.reconsumeToken();
                    if (try self.consumeQualifiedRule()) |rule| {
                        try rules.append(rule);
                    }
                },
            }
        } else {
            return try rules.toOwnedSlice();
        }
    }
}

fn consumeQualifiedRule(self: *Parser) !?Stylesheet.Rule {
    var selectors = std.ArrayList(Stylesheet.Rule.Selector).init(self.arena.allocator());

    while (true) {
        if (self.consumeToken()) |token| {
            switch (token) {
                .l_curly_bracket => {
                    self.reconsumeToken();

                    return .{
                        .selectors = try selectors.toOwnedSlice(),
                        .declarations = try self.consumeDeclarationList(),
                    };
                },
                else => {
                    self.reconsumeToken();
                    try selectors.append(try self.consumeSelector());
                    self.skipWhitespace();
                },
            }
        } else {
            return null;
        }
    }
}

fn consumeDeclaration(self: *Parser) !?Stylesheet.Rule.Declaration {
    if (self.consumeToken()) |property_token| {
        switch (property_token) {
            .ident => |property_ident| {
                const raw_property_name = property_ident.slice(self.source);
                const property_name = try std.ascii.allocLowerString(
                    self.arena.allocator(),
                    raw_property_name,
                );

                self.skipWhitespace();

                if (self.consumeToken()) |colon_token| {
                    if (colon_token != .colon) {
                        @panic("TODO");
                    }
                } else {
                    @panic("TODO");
                }

                self.skipWhitespace();

                var decl_tokens = std.ArrayList(Stylesheet.Rule.Declaration.Token).init(self.arena.allocator());

                while (self.peekToken() != null and self.peekToken().? != .semicolon) {
                    try decl_tokens.append(self.consumeDeclarationToken());
                }

                if (decl_tokens.items.len == 0) {
                    @panic("TODO");
                }

                return .{
                    .property = property_name,
                    .value = try decl_tokens.toOwnedSlice(),
                };
            },
            else => @panic("TODO"),
        }
    } else {
        @panic("TODO");
    }
}

fn consumeStyleBlockContent(self: *Parser) void {
    _ = self;
    @panic("TODO");
}

fn consumeDeclarationList(self: *Parser) ![]const Stylesheet.Rule.Declaration {
    if (self.peekToken() == null or self.peekToken().? != .l_curly_bracket) {
        @panic("TODO");
    }
    _ = self.consumeToken();

    var declarations = std.ArrayList(Stylesheet.Rule.Declaration).init(self.arena.allocator());

    while (true) {
        if (self.consumeToken()) |token| {
            switch (token) {
                .whitespace, .semicolon => {},
                .ident => {
                    self.reconsumeToken();
                    if (try self.consumeDeclaration()) |decl| {
                        try declarations.append(decl);
                    } else {
                        @panic("TODO");
                    }
                },
                .r_curly_bracket => break,
                else => @panic("TODO"),
            }
        } else {
            @panic("TODO");
        }
    }

    return try declarations.toOwnedSlice();
}

fn consumeSelector(self: *Parser) !Stylesheet.Rule.Selector {
    return .{ .simple = try self.consumeSimpleSelector() };
}

fn consumeSimpleSelector(self: *Parser) !Stylesheet.Rule.Selector.Simple {
    var selector: Stylesheet.Rule.Selector.Simple = .{
        .element_name = null,
        .id = null,
        .class = undefined,
    };

    var class = std.ArrayList([]const u8).init(self.arena.allocator());

    if (self.peekToken() != null and self.peekToken().? == .delim and self.peekToken().?.delim == '*') {
        _ = self.consumeToken();
    } else if (self.peekToken() != null and self.peekToken().? == .ident) {
        const ident = self.consumeToken().?.ident;

        selector.element_name = try std.ascii.allocLowerString(
            self.arena.allocator(),
            ident.slice(self.source),
        );
    }

    while (true) {
        if (self.peekToken()) |token| {
            switch (token) {
                .hash => @panic("TODO"),
                .delim => |delim| switch (delim) {
                    '.' => @panic("TODO"),
                    else => break,
                },
                else => break,
            }
        } else {
            break;
        }
    }

    selector.class = try class.toOwnedSlice();

    return selector;
}

fn consumeDeclarationToken(self: *Parser) Stylesheet.Rule.Declaration.Token {
    if (self.consumeToken()) |token| {
        switch (token) {
            .hash => |hash| {
                // Format: 0xRRGGBB
                const hex: u24 = switch (hash.span.slice(self.source).len) {
                    3 => @panic("TODO"),
                    6 => std.fmt.parseInt(
                        u24,
                        hash.span.slice(self.source),
                        16,
                    ) catch @panic("TODO"),
                    else => @panic("TODO"),
                };

                return .{
                    .color = .{
                        .rgb = .{
                            .r = @truncate(hex >> 16),
                            .g = @truncate(hex >> 8),
                            .b = @truncate(hex),
                        },
                    },
                };
            },
            else => @panic("TODO"),
        }
    } else {
        @panic("TODO");
    }
}
