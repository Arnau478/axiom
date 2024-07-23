const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");
const Dom = @import("Dom.zig");

const Parser = @This();

allocator: std.mem.Allocator,
source: []const u8,
tokens: []const Tokenizer.Token,
pos: usize,
dom: *Dom,
insertion_mode: InsertionMode,
use_rules: ?InsertionMode,
can_change_mode: bool,
is_fragment: bool,
open_elements: std.ArrayListUnmanaged(*Dom.Element),
active_formatting_elements: std.ArrayListUnmanaged(*Dom.Element),
head: ?*Dom.Element,
frameset_ok: bool,

pub const InsertionMode = enum {
    initial,
    before_html,
    before_head,
    in_head,
    after_head,
    in_body,
    after_body,
    after_after_body,
};

pub fn init(allocator: std.mem.Allocator, source: []const u8, dom: *Dom) !Parser {
    var tokens = std.ArrayList(Tokenizer.Token).init(allocator);
    try tokens.ensureTotalCapacity(@divFloor(source.len, 10)); // TODO: Is this a good value?

    var tokenizer = Tokenizer{
        .source = source,
    };

    while (tokenizer.scanToken()) |token| {
        try tokens.append(token);
    }

    return .{
        .allocator = allocator,
        .source = source,
        .tokens = try tokens.toOwnedSlice(),
        .pos = 0,
        .dom = dom,
        .insertion_mode = .initial,
        .use_rules = null,
        .can_change_mode = true,
        .is_fragment = false,
        .open_elements = .{},
        .active_formatting_elements = .{},
        .head = null,
        .frameset_ok = true,
    };
}

pub fn deinit(self: *Parser) void {
    self.allocator.free(self.tokens);
    self.open_elements.deinit(self.allocator);
}

fn pushElement(self: *Parser, element: *Dom.Element) !void {
    try self.open_elements.append(self.allocator, element);
}

fn popElement(self: *Parser) *Dom.Element {
    return self.open_elements.pop();
}

fn currentElement(self: *Parser) *Dom.Element {
    return self.open_elements.getLast();
}

fn consume(self: *Parser) ?Tokenizer.Token {
    defer self.pos += 1;
    return self.peek();
}

fn peek(self: *Parser) ?Tokenizer.Token {
    if (self.pos >= self.tokens.len) return null;
    return self.tokens[self.pos];
}

fn reconsume(self: *Parser) void {
    self.pos -= 1;
}

fn isInScope(self: Parser, tag_name: []const u8) bool {
    return self.isInSpecificScope(tag_name, &.{
        "applet",
        "caption",
        "html",
        "table",
        "td",
        "th",
        "marquee",
        "object",
        "template",
        // TODO: Support MathML and SVG
    });
}

fn isInSpecificScope(self: Parser, tag_name: []const u8, scope: []const []const u8) bool {
    var iter = std.mem.reverseIterator(self.open_elements.items);

    while (iter.next()) |element| {
        if (std.mem.eql(u8, element.tag_name, tag_name)) {
            return true;
        } else {
            for (scope) |scope_element| {
                if (std.mem.eql(u8, element.tag_name, scope_element)) {
                    return false;
                }
            }
        }
    }

    unreachable;
}

fn createElementFromToken(self: Parser, token: Tokenizer.Token) !Dom.Element {
    // TODO: Follow the spec

    const raw_name = token.start_tag.raw_name.slice(self.source);

    const name = try std.ascii.allocLowerString(self.dom.allocator, raw_name);
    errdefer self.dom.allocator.free(name);

    return .{
        .tag_name = name,
        .children = .{},
    };
}

fn insertHtmlElementFromToken(self: *Parser, token: Tokenizer.Token) !*Dom.Element {
    // TODO: Follow the spec

    const element = try self.dom.allocator.create(Dom.Element);
    errdefer self.dom.allocator.destroy(element);

    element.* = try self.createElementFromToken(token);

    try self.currentElement().children.append(self.dom.allocator, .{ .element = element });

    try self.pushElement(element);

    return element;
}

fn insertCharacter(self: *Parser, char: u8) !void {
    if (self.currentElement().children.items.len != 0 and self.currentElement().children.getLast() == .text) {
        try self.currentElement().children.getLast().text.data.append(self.dom.allocator, char);
    } else {
        const text = try self.dom.allocator.create(Dom.Text);
        errdefer self.dom.allocator.destroy(text);
        text.* = .{
            .data = .{},
        };
        try text.data.append(self.dom.allocator, char);
        try self.currentElement().children.append(self.dom.allocator, .{ .text = text });
    }
}

fn scriptingEnabled(self: Parser) bool {
    // TODO: Support scripting
    _ = self;

    return false;
}

fn stopParser(self: *Parser) void {
    // TODO: Follow the spec

    for (0..self.open_elements.items.len) |_| _ = self.popElement();
}

pub fn parse(self: *Parser) !void {
    while (true) {
        const mode = mode: {
            if (self.use_rules) |mode| {
                self.use_rules = null;
                break :mode mode;
            } else {
                break :mode self.insertion_mode;
            }
        };

        switch (mode) {
            .initial => {
                var other = false;

                if (self.consume()) |token| {
                    switch (token) {
                        .char => @panic("TODO"),
                        .comment => @panic("TODO"),
                        .doctype => |doctype| {
                            if (!std.ascii.eqlIgnoreCase(doctype.raw_name.slice(self.source), "html")) { // TODO: check everything
                                @panic("TODO");
                            }

                            self.dom.document.doctype = .{
                                .name = try std.ascii.allocLowerString(self.dom.allocator, doctype.raw_name.slice(self.source)),
                                .public = try self.dom.allocator.dupe(u8, if (doctype.public) |public| public.slice(self.source) else ""),
                                .system = try self.dom.allocator.dupe(u8, if (doctype.system) |system| system.slice(self.source) else ""),
                            };

                            if (self.can_change_mode) {
                                const public = if (doctype.public) |public| public.slice(self.source) else "";
                                const system = if (doctype.system) |system| system.slice(self.source) else "";

                                if (doctype.force_quirks or
                                    !std.ascii.eqlIgnoreCase(doctype.raw_name.slice(self.source), "html") or
                                    std.ascii.eqlIgnoreCase(public, "-//W3O//DTD W3 HTML Strict 3.0//EN//") or
                                    std.ascii.eqlIgnoreCase(public, "-/W3C/DTD HTML 4.0 Transitional/EN") or
                                    std.ascii.eqlIgnoreCase(public, "HTML") or
                                    std.ascii.eqlIgnoreCase(system, "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd") or
                                    std.ascii.startsWithIgnoreCase(public, "+//Silmaril//dtd html Pro v0r11 19970101//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//AS//DTD HTML 3.0 asWedit + extensions//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//AdvaSoft Ltd//DTD HTML 3.0 asWedit + extensions//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML 2.0 Level 1//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML 2.0 Level 2//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML 2.0 Strict Level 1//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML 2.0 Strict Level 2//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML 2.0 Strict//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML 2.0//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML 2.1E//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML 3.0//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML 3.2 Final//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML 3.2//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML 3//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML Level 0//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML Level 1//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML Level 2//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML Level 3//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML Strict Level 0//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML Strict Level 1//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML Strict Level 2//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML Strict Level 3//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML Strict//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//IETF//DTD HTML//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//Metrius//DTD Metrius Presentational//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//Microsoft//DTD Internet Explorer 2.0 HTML Strict//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//Microsoft//DTD Internet Explorer 2.0 HTML//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//Microsoft//DTD Internet Explorer 2.0 Tables//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//Microsoft//DTD Internet Explorer 3.0 HTML Strict//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//Microsoft//DTD Internet Explorer 3.0 HTML//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//Microsoft//DTD Internet Explorer 3.0 Tables//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//Netscape Comm. Corp.//DTD HTML//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//Netscape Comm. Corp.//DTD Strict HTML//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//O'Reilly and Associates//DTD HTML 2.0//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//O'Reilly and Associates//DTD HTML Extended 1.0//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//O'Reilly and Associates//DTD HTML Extended Relaxed 1.0//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//SQ//DTD HTML 2.0 HoTMetaL + extensions//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//SoftQuad Software//DTD HoTMetaL PRO 6.0::19990601::extensions to HTML 4.0//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//SoftQuad//DTD HoTMetaL PRO 4.0::19971010::extensions to HTML 4.0//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//Spyglass//DTD HTML 2.0 Extended//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//Sun Microsystems Corp.//DTD HotJava HTML//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//Sun Microsystems Corp.//DTD HotJava Strict HTML//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//W3C//DTD HTML 3 1995-03-24//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//W3C//DTD HTML 3.2 Draft//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//W3C//DTD HTML 3.2 Final//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//W3C//DTD HTML 3.2//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//W3C//DTD HTML 3.2S Draft//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//W3C//DTD HTML 4.0 Frameset//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//W3C//DTD HTML 4.0 Transitional//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//W3C//DTD HTML Experimental 19960712//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//W3C//DTD HTML Experimental 970421//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//W3C//DTD W3 HTML//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//W3O//DTD W3 HTML 3.0//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//WebTechs//DTD Mozilla HTML 2.0//") or
                                    std.ascii.startsWithIgnoreCase(public, "-//WebTechs//DTD Mozilla HTML//") or
                                    (doctype.system == null and std.ascii.startsWithIgnoreCase(public, "-//W3C//DTD HTML 4.01 Frameset//")) or
                                    (doctype.system == null and std.ascii.startsWithIgnoreCase(public, "-//W3C//DTD HTML 4.01 Transitional//")))
                                {
                                    self.dom.document.mode = .quirks;
                                } else if (std.mem.startsWith(u8, public, "-//W3C//DTD XHTML 1.0 Frameset//") or
                                    std.mem.startsWith(u8, public, "-//W3C//DTD XHTML 1.0 Transitional//") or
                                    (doctype.system != null and std.mem.startsWith(u8, public, "-//W3C//DTD HTML 4.01 Frameset//")) or
                                    (doctype.system != null and std.mem.startsWith(u8, public, "-//W3C//DTD HTML 4.01 Transitional//")))
                                {
                                    self.dom.document.mode = .limited_quirks;
                                }

                                self.insertion_mode = .before_html;
                                continue;
                            } else {
                                @panic("TODO");
                            }
                        },
                        else => other = true,
                    }
                } else {
                    @panic("TODO");
                }

                if (other) {
                    @panic("TODO");
                } else {
                    unreachable;
                }
            },
            .before_html => {
                var other = false;

                if (self.consume()) |token| {
                    switch (token) {
                        .doctype => @panic("TODO"),
                        .comment => @panic("TODO"),
                        .char => |char| switch (char.char(self.source)) {
                            '\t', '\n', 0x0C, '\r', ' ' => continue,
                            else => other = true,
                        },
                        .start_tag => |start_tag| {
                            if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "html")) {
                                if (self.dom.document.root) |_| {
                                    @panic("TODO");
                                }

                                const element = try self.dom.allocator.create(Dom.Element);
                                errdefer self.dom.allocator.destroy(element);

                                element.* = try self.createElementFromToken(token);

                                self.dom.document.root = element;

                                try self.pushElement(element);

                                self.insertion_mode = .before_head;
                                continue;
                            } else {
                                other = true;
                            }
                        },
                        .end_tag => |end_tag| {
                            if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "head") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "body") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "html") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "br"))
                            {
                                other = true;
                            } else {
                                @panic("TODO");
                            }
                        },
                    }
                } else {
                    @panic("TODO");
                }

                if (other) {
                    @panic("TODO");
                } else {
                    unreachable;
                }
            },
            .before_head => {
                var other = false;

                if (self.consume()) |token| {
                    switch (token) {
                        .char => |char| switch (char.char(self.source)) {
                            '\t', '\n', 0x0C, '\r', ' ' => continue,
                            else => other = true,
                        },
                        .comment => @panic("TODO"),
                        .doctype => @panic("TODO"),
                        .start_tag => |start_tag| {
                            if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "html")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "head")) {
                                const element = try self.insertHtmlElementFromToken(token);
                                self.head = element;
                                self.insertion_mode = .in_head;
                                continue;
                            } else {
                                other = true;
                            }
                        },
                        .end_tag => |end_tag| {
                            if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "head") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "body") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "html") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "br"))
                            {
                                other = true;
                            } else {
                                @panic("TODO");
                            }
                        },
                    }
                } else {
                    @panic("TODO");
                }

                if (other) {
                    @panic("TODO");
                } else {
                    unreachable;
                }
            },
            .in_head => {
                var other = false;

                if (self.consume()) |token| {
                    switch (token) {
                        .char => |char| switch (char.char(self.source)) {
                            '\t', '\n', 0x0C, '\r', ' ' => |c| {
                                try self.insertCharacter(c);
                                continue;
                            },
                            else => other = true,
                        },
                        .comment => @panic("TODO"),
                        .doctype => @panic("TODO"),
                        .start_tag => |start_tag| {
                            if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "html")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "base") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "basefont") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "bgsound") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "link"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "meta")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "title")) {
                                @panic("TODO");
                            } else if ((std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "noscript") and self.scriptingEnabled()) or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "noframes") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "style"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "noscript") and !self.scriptingEnabled()) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "script")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "template")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "head")) {
                                @panic("TODO");
                            } else {
                                other = true;
                            }
                        },
                        .end_tag => |end_tag| {
                            if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "head")) {
                                const head = self.popElement();
                                std.debug.assert(std.mem.eql(u8, head.tag_name, "head"));

                                self.insertion_mode = .after_head;
                                continue;
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "body") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "html") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "br"))
                            {
                                other = true;
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "template")) {
                                @panic("TODO");
                            } else {
                                @panic("TODO");
                            }
                        },
                    }
                } else {
                    @panic("TODO");
                }

                if (other) {
                    @panic("TODO");
                } else {
                    unreachable;
                }
            },
            .after_head => {
                var other = false;

                if (self.consume()) |token| {
                    switch (token) {
                        .char => |char| switch (char.char(self.source)) {
                            '\t', '\n', 0x0C, '\r', ' ' => |c| {
                                try self.insertCharacter(c);
                                continue;
                            },
                            else => other = true,
                        },
                        .comment => @panic("TODO"),
                        .doctype => @panic("TODO"),
                        .start_tag => |start_tag| {
                            if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "html")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "body")) {
                                _ = try self.insertHtmlElementFromToken(token);
                                self.frameset_ok = false;

                                self.insertion_mode = .in_body;
                                continue;
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "frameset")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "base") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "basefont") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "bgsound") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "link") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "meta") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "noframes") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "script") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "style") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "template") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "title"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "head")) {
                                @panic("TODO");
                            } else {
                                other = true;
                            }
                        },
                        .end_tag => |end_tag| {
                            if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "template")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "body") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "html") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "br"))
                            {
                                @panic("TODO");
                            } else {
                                @panic("TODO");
                            }
                        },
                    }
                } else {
                    @panic("TODO");
                }

                if (other) {
                    @panic("TODO");
                } else {
                    unreachable;
                }
            },
            .in_body => {
                if (self.consume()) |token| {
                    switch (token) {
                        .char => |char| switch (char.char(self.source)) {
                            0 => @panic("TODO"),
                            '\t', '\n', 0x0C, '\r', ' ' => |c| {
                                if (self.active_formatting_elements.items.len != 0) {
                                    @panic("TODO");
                                }

                                try self.insertCharacter(c);
                                continue;
                            },
                            else => |c| {
                                if (self.active_formatting_elements.items.len != 0) {
                                    @panic("TODO");
                                }

                                try self.insertCharacter(c);
                                self.frameset_ok = false;
                                continue;
                            },
                        },
                        .comment => @panic("TODO"),
                        .doctype => @panic("TODO"),
                        .start_tag => |start_tag| {
                            if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "html")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "base") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "basefont") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "bgsound") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "link") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "meta") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "noframes") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "script") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "style") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "template") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "title"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "body")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "frameset")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "address") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "article") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "aside") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "blockquote") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "center") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "details") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "dialog") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "dir") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "div") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "dl") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "fieldset") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "figcaption") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "figure") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "footer") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "header") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "hgroup") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "main") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "menu") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "nav") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "ol") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "p") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "search") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "section") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "summary") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "ul"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "h1") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "h2") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "h3") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "h4") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "h5") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "h6"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "pre") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "listing"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "form")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "li")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "dd") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "dt"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "plaintext")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "button")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "a")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "b") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "big") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "code") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "em") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "font") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "i") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "s") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "small") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "strike") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "strong") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "tt") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "u"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "nobr")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "applet") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "marquee") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "object"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "table")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "area") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "br") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "embed") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "img") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "keygen") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "wbr"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "input")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "param") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "source") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "track"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "hr")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "image")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "textarea")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "xmp")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "iframe")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "noembed") or
                                (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "noscript") and self.scriptingEnabled()))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "select")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "optgroup") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "option"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "rb") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "rtc"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "rp") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "rt"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "math")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "svg")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "caption") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "col") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "colgroup") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "frame") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "head") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "tbody") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "td") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "tfoot") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "th") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "thead") or
                                std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "tr"))
                            {
                                @panic("TODO");
                            } else {
                                @panic("TODO");
                            }
                        },
                        .end_tag => |end_tag| {
                            if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "template")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "body")) {
                                if (self.isInScope("body")) {
                                    for (self.open_elements.items) |element| {
                                        if (!std.mem.eql(u8, element.tag_name, "dd") and
                                            !std.mem.eql(u8, element.tag_name, "dt") and
                                            !std.mem.eql(u8, element.tag_name, "li") and
                                            !std.mem.eql(u8, element.tag_name, "optgroup") and
                                            !std.mem.eql(u8, element.tag_name, "option") and
                                            !std.mem.eql(u8, element.tag_name, "p") and
                                            !std.mem.eql(u8, element.tag_name, "rb") and
                                            !std.mem.eql(u8, element.tag_name, "rp") and
                                            !std.mem.eql(u8, element.tag_name, "rt") and
                                            !std.mem.eql(u8, element.tag_name, "rtc") and
                                            !std.mem.eql(u8, element.tag_name, "tbody") and
                                            !std.mem.eql(u8, element.tag_name, "td") and
                                            !std.mem.eql(u8, element.tag_name, "tfoot") and
                                            !std.mem.eql(u8, element.tag_name, "th") and
                                            !std.mem.eql(u8, element.tag_name, "thead") and
                                            !std.mem.eql(u8, element.tag_name, "tr") and
                                            !std.mem.eql(u8, element.tag_name, "body") and
                                            !std.mem.eql(u8, element.tag_name, "html"))
                                        {
                                            @panic("TODO");
                                        }
                                    }
                                } else {
                                    @panic("TODO");
                                }

                                self.insertion_mode = .after_body;
                                continue;
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "html")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "address") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "article") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "aside") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "blockquote") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "button") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "center") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "details") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "dialog") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "dir") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "div") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "dl") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "fieldset") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "figcaption") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "figure") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "footer") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "header") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "hgroup") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "listing") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "main") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "menu") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "nav") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "ol") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "pre") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "search") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "section") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "summary") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "ul"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "form")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "p")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "li")) {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "dd") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "dt"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "h1") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "h2") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "h3") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "h4") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "h5") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "h6"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "a") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "b") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "big") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "code") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "em") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "font") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "i") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "nobr") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "s") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "small") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "strike") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "strong") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "tt") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "u"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "applet") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "marquee") or
                                std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "object"))
                            {
                                @panic("TODO");
                            } else if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "br")) {
                                @panic("TODO");
                            } else {
                                @panic("TODO");
                            }
                        },
                    }
                } else {
                    @panic("TODO");
                }
            },
            .after_body => {
                var other = false;

                if (self.consume()) |token| {
                    switch (token) {
                        .char => |char| switch (char.char(self.source)) {
                            '\t', '\n', 0x0C, '\r', ' ' => {
                                self.reconsume();
                                self.use_rules = .in_body;
                                continue;
                            },
                            else => other = true,
                        },
                        .comment => @panic("TODO"),
                        .doctype => @panic("TODO"),
                        .start_tag => |start_tag| {
                            if (std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "html")) {
                                @panic("TODO");
                            } else {
                                other = true;
                            }
                        },
                        .end_tag => |end_tag| {
                            if (std.ascii.eqlIgnoreCase(end_tag.raw_name.slice(self.source), "html")) {
                                if (self.is_fragment) {
                                    @panic("TODO");
                                } else {
                                    self.insertion_mode = .after_after_body;
                                    continue;
                                }
                            } else {
                                other = true;
                            }
                        },
                    }
                } else {
                    @panic("TODO");
                }

                if (other) {
                    @panic("TODO");
                } else {
                    unreachable;
                }
            },
            .after_after_body => {
                var other = false;

                if (self.consume()) |token| {
                    switch (token) {
                        .comment => @panic("TODO"),
                        .doctype, .char, .start_tag => {
                            if (switch (token) {
                                .doctype => true,
                                .char => |char| switch (char.char(self.source)) {
                                    '\t', '\n', 0x0C, '\r', ' ' => true,
                                    else => false,
                                },
                                .start_tag => |start_tag| std.ascii.eqlIgnoreCase(start_tag.raw_name.slice(self.source), "html"),
                                else => unreachable,
                            }) {
                                @panic("TODO");
                            } else {
                                other = true;
                            }
                        },
                        else => other = true,
                    }
                } else {
                    self.stopParser();
                    return;
                }

                if (other) {
                    @panic("TODO");
                } else {
                    unreachable;
                }
            },
        }
    }
}
