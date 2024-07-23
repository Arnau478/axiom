const std = @import("std");
const html = @import("html");
const css = @import("css");

const Color = @import("../Color.zig");
const EdgeSizes = @import("EdgeSizes.zig");

const Style = @This();

color: Color,
background_color: Color,
padding: EdgeSizes,

const default_style: Style = .{
    .color = .{ .r = 0, .g = 0, .b = 0 },
    .background_color = .{ .r = 255, .g = 255, .b = 255 },
    .padding = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
};

pub const Property = enum {
    color,
    @"background-color",
    @"padding-top",
    @"padding-right",
    @"padding-bottom",
    @"padding-left",
    padding,

    pub const Grammar = union(enum) {
        const Token = css.Stylesheet.Rule.Declaration.Token;

        const ParseState = struct {
            tokens: []const Token,
            pos: usize,

            pub fn peekToken(self: ParseState) ?Token {
                if (self.pos >= self.tokens.len) return null;

                return self.tokens[self.pos];
            }

            pub fn readToken(self: *ParseState) ?Token {
                const tok = self.peekToken() orelse return null;
                self.pos += 1;
                return tok;
            }
        };

        token: @typeInfo(Token).Union.tag_type.?,
        juxtaposed: []const struct { name: [:0]const u8, grammar: Grammar },

        fn Result(comptime self: Grammar) type {
            return switch (self) {
                .token => |tag| std.meta.FieldType(Token, tag),
                .juxtaposed => |juxtaposed| T: {
                    var fields: [juxtaposed.len]std.builtin.Type.StructField = undefined;

                    for (juxtaposed, &fields) |element, *field| {
                        field.* = .{
                            .name = element.name,
                            .type = element.grammar.Result(),
                            .default_value = null,
                            .is_comptime = false,
                            .alignment = @alignOf(element.grammar.Result()),
                        };
                    }

                    break :T @Type(.{
                        .Struct = .{
                            .layout = .auto,
                            .fields = &fields,
                            .decls = &.{},
                            .is_tuple = false,
                        },
                    });
                },
            };
        }

        fn parse(comptime self: Grammar, state: *ParseState) !self.Result() {
            switch (self) {
                .token => |tag| {
                    const token = state.readToken() orelse return error.InvalidValue;
                    if (std.meta.activeTag(token) != tag) return error.InvalidValue;
                    return @field(token, @tagName(tag));
                },
                .juxtaposed => |juxtaposed| {
                    var res: self.Result() = undefined;

                    inline for (juxtaposed) |element| {
                        @field(res, element.name) = try element.grammar.parse(state);
                    }

                    return res;
                },
            }
        }
    };

    pub fn grammar(comptime self: Property) Grammar {
        return switch (self) {
            .color => .{ .token = .color },
            .@"background-color" => .{ .token = .color },
            .@"padding-top" => .{ .token = .length },
            .@"padding-right" => .{ .token = .length },
            .@"padding-bottom" => .{ .token = .length },
            .@"padding-left" => .{ .token = .length },
            .padding => .{ .juxtaposed = &.{
                .{ .name = "top", .grammar = .{ .token = .length } },
                .{ .name = "right", .grammar = .{ .token = .length } },
                .{ .name = "bottom", .grammar = .{ .token = .length } },
                .{ .name = "left", .grammar = .{ .token = .length } },
            } },
        };
    }

    pub fn parse(comptime self: Property, tokens: []const Grammar.Token) !self.grammar().Result() {
        var state = Grammar.ParseState{ .tokens = tokens, .pos = 0 };
        const res = try (comptime self.grammar()).parse(&state);
        if (state.pos != tokens.len) return error.InvalidValue;
        return res;
    }
};

pub fn get(element: html.Dom.Element, stylesheet: css.Stylesheet) Style {
    // TODO: Respect specificity

    var style: Style = default_style;

    for (stylesheet.rules) |rule| {
        if (rule.matches(element)) {
            for (rule.declarations) |declaration| {
                if (std.meta.stringToEnum(Property, declaration.property)) |property| {
                    switch (property) {
                        inline .color => |p| {
                            const value = (p.parse(declaration.value) catch @panic("TODO")).toRgb();
                            style.color.r = value.r;
                            style.color.g = value.g;
                            style.color.b = value.b;
                        },
                        inline .@"background-color" => |p| {
                            const value = (p.parse(declaration.value) catch @panic("TODO")).toRgb();
                            style.background_color.r = value.r;
                            style.background_color.g = value.g;
                            style.background_color.b = value.b;
                        },
                        inline .@"padding-top" => |p| style.padding.top = resolveLength(p.parse(declaration.value) catch @panic("TODO")),
                        inline .@"padding-right" => |p| style.padding.right = resolveLength(p.parse(declaration.value) catch @panic("TODO")),
                        inline .@"padding-bottom" => |p| style.padding.bottom = resolveLength(p.parse(declaration.value) catch @panic("TODO")),
                        inline .@"padding-left" => |p| style.padding.left = resolveLength(p.parse(declaration.value) catch @panic("TODO")),
                        inline .padding => @panic("TODO"),
                    }
                } else {
                    @panic("TODO");
                }
            }
        }
    }

    return style;
}

fn resolveLength(length: css.Stylesheet.Rule.Declaration.Token.Length) f64 {
    switch (length.unit) {
        .px => return length.magnitude,
        else => @panic("TODO"),
    }
}

test "simple property grammar" {
    try std.testing.expectEqualDeep(
        Property.Grammar.Token.Color{ .rgb = .{ .r = 0xff, .g = 0x00, .b = 0x00 } },
        try Property.color.parse(&.{.{ .color = .{ .rgb = .{ .r = 0xff, .g = 0x00, .b = 0x00 } } }}),
    );

    try std.testing.expectEqualDeep(
        Property.Grammar.Token.Color{ .rgb = .{ .r = 0xff, .g = 0x00, .b = 0xff } },
        try Property.@"background-color".parse(&.{.{ .color = .{ .rgb = .{ .r = 0xff, .g = 0x00, .b = 0xff } } }}),
    );

    try std.testing.expectError(
        error.InvalidValue,
        Property.color.parse(&.{
            .{ .color = .{ .rgb = .{ .r = 0xff, .g = 0x00, .b = 0x00 } } },
            .{ .color = .{ .rgb = .{ .r = 0xff, .g = 0x00, .b = 0x00 } } },
        }),
    );
}

test "juxtaposed property grammar" {
    try std.testing.expectEqualDeep(
        Property.padding.grammar().Result(){
            .top = .{ .magnitude = 10, .unit = .px },
            .right = .{ .magnitude = 20, .unit = .px },
            .bottom = .{ .magnitude = 30, .unit = .px },
            .left = .{ .magnitude = 40, .unit = .px },
        },
        try Property.padding.parse(&.{
            .{ .length = .{ .magnitude = 10, .unit = .px } },
            .{ .length = .{ .magnitude = 20, .unit = .px } },
            .{ .length = .{ .magnitude = 30, .unit = .px } },
            .{ .length = .{ .magnitude = 40, .unit = .px } },
        }),
    );
}
