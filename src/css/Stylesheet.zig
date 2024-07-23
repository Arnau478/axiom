const std = @import("std");
const html = @import("html");
const Specificity = @import("Specificity.zig");

const Stylesheet = @This();

location: ?[]const u8,
rules: []const Rule,

pub const Rule = struct {
    selectors: []const Selector,
    declarations: []const Declaration,

    pub const Selector = union(enum) {
        simple: Simple,

        pub const Simple = struct {
            element_name: ?[]const u8,
            id: ?[]const u8,
            class: []const []const u8,

            pub fn specificity(self: Simple) Specificity {
                return .{
                    .a = if (self.id) |_| 1 else 0,
                    .b = self.class.len,
                    .c = if (self.element_name) |_| 1 else 0,
                };
            }

            pub fn render(self: Simple, writer: anytype) !void {
                try writer.print("{s}", .{self.element_name orelse ""});
            }

            pub fn matches(self: Simple, element: html.Dom.Element) bool {
                if (self.element_name) |element_name| {
                    if (!std.mem.eql(u8, element_name, element.tag_name)) return false;
                }

                // TODO: id
                // TODO: class

                return true;
            }
        };

        pub fn specificity(self: Selector) Specificity {
            return switch (self) {
                inline else => |s| s.specificity(),
            };
        }

        pub fn matches(self: Selector, element: html.Dom.Element) bool {
            return switch (self) {
                inline else => |s| s.matches(element),
            };
        }

        pub fn render(self: Selector, writer: anytype) !void {
            switch (self) {
                inline else => |s| try s.render(writer),
            }
        }
    };

    pub const Declaration = struct {
        property: []const u8,
        value: []const Token,

        pub const Token = union(enum) {
            slash,
            comma,
            length: Length,
            percentage: f64,
            number: f64,
            color: Color,

            pub const Length = struct {
                magnitude: f64,
                unit: Unit,

                pub const Unit = enum {
                    px,
                    ex,
                    em,
                    in,
                    cm,
                    mm,
                    pt,
                    pc,
                };
            };

            pub const Color = union(enum) {
                rgb: Rgb,
                named: Named,

                const Rgb = struct {
                    r: u8,
                    g: u8,
                    b: u8,
                };

                const Named = enum {
                    maroon,
                    red,
                    orange,
                    yellow,
                    olive,
                    purple,
                    fuchsia,
                    white,
                    lime,
                    green,
                    navy,
                    blue,
                    aqua,
                    teal,
                    black,
                    silver,
                    gray,

                    pub fn toRgb(self: Named) Rgb {
                        return switch (self) {
                            .maroon => .{ .r = 0x80, .g = 0x00, .b = 0x00 },
                            .red => .{ .r = 0xff, .g = 0x00, .b = 0x00 },
                            .orange => .{ .r = 0xff, .g = 0xa5, .b = 0x00 },
                            .yellow => .{ .r = 0xff, .g = 0xff, .b = 0x00 },
                            .olive => .{ .r = 0x80, .g = 0x80, .b = 0x00 },
                            .purple => .{ .r = 0x80, .g = 0x00, .b = 0x80 },
                            .fuchsia => .{ .r = 0xff, .g = 0x00, .b = 0xff },
                            .white => .{ .r = 0xff, .g = 0xff, .b = 0xff },
                            .lime => .{ .r = 0x00, .g = 0xff, .b = 0x00 },
                            .green => .{ .r = 0x00, .g = 0x80, .b = 0x00 },
                            .navy => .{ .r = 0x00, .g = 0x00, .b = 0x80 },
                            .blue => .{ .r = 0x00, .g = 0x00, .b = 0xff },
                            .aqua => .{ .r = 0x00, .g = 0xff, .b = 0xff },
                            .teal => .{ .r = 0x00, .g = 0x80, .b = 0x80 },
                            .black => .{ .r = 0x00, .g = 0x00, .b = 0x00 },
                            .silver => .{ .r = 0xc0, .g = 0xc0, .b = 0xc0 },
                            .gray => .{ .r = 0x80, .g = 0x80, .b = 0x80 },
                        };
                    }
                };

                pub fn toRgb(self: Color) Rgb {
                    return switch (self) {
                        .rgb => |rgb| rgb,
                        inline else => |c| c.toRgb(),
                    };
                }
            };

            pub fn render(self: Token, writer: anytype) !void {
                switch (self) {
                    .slash => _ = try writer.write("/"),
                    .comma => _ = try writer.write(","),
                    .length => |length| try writer.print("{d}{s}", .{ length.magnitude, @tagName(length.unit) }),
                    .percentage => |percentage| try writer.print("{d}%", .{percentage}),
                    .number => |number| try writer.print("{d}", .{number}),
                    .color => |color| {
                        switch (color) {
                            .rgb => |rgb| {
                                try writer.print("#{x:0>2}{x:0>2}{x:0>2}", .{ rgb.r, rgb.g, rgb.b });
                            },
                            .named => |named| _ = try writer.write(@tagName(named)),
                        }
                    },
                }
            }
        };

        pub fn render(self: Declaration, writer: anytype) !void {
            try writer.print("{s}:", .{self.property});
            for (self.value) |item| {
                _ = try writer.write(" ");
                try item.render(writer);
            }
            _ = try writer.write(";");
        }
    };

    pub fn specificity(self: Rule) Specificity {
        var spec = Specificity{ .a = 0, .b = 0, .c = 0 };

        for (self.selectors) |sel| {
            spec = spec.add(sel.specificity());
        }

        return spec;
    }

    pub fn matches(self: Rule, element: html.Dom.Element) bool {
        for (self.selectors) |selector| {
            if (selector.matches(element)) return true;
        }

        return false;
    }

    pub fn render(self: Rule, writer: anytype) !void {
        for (self.selectors) |selector| {
            try selector.render(writer);
            _ = try writer.write(" ");
        }

        _ = try writer.write("{");

        for (self.declarations) |declaration| {
            _ = try writer.write("\n    ");
            try declaration.render(writer);
        }

        if (self.declarations.len != 0) {
            _ = try writer.write("\n");
        }

        _ = try writer.write("}");
    }
};

pub fn render(self: Stylesheet, writer: anytype) !void {
    for (self.rules, 0..) |rule, i| {
        if (i != 0) try writer.print("\n\n", .{});
        try rule.render(writer);
    }
}
