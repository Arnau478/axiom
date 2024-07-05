const std = @import("std");
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
        };

        pub fn specificity(self: Selector) Specificity {
            return switch (self) {
                inline else => |s| s.specificity(),
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
        value: Value,

        pub fn render(self: Declaration, writer: anytype) !void {
            try writer.print("{s}: ", .{self.property});
            try self.value.render(writer);
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

pub const Value = union(enum) {
    color: Color,

    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,

        pub fn render(self: Color, writer: anytype) !void {
            try writer.print("#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b });
            if (self.a != 255) {
                try writer.print("{x:0>2}", .{self.a});
            }
        }
    };

    pub fn render(self: Value, writer: anytype) !void {
        switch (self) {
            inline else => |v| try v.render(writer),
        }
    }
};
