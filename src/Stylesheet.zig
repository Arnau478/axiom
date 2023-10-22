const std = @import("std");

const Stylesheet = @This();

pub const PropertyMap = std.StringHashMap(Stylesheet.Value);

pub const Display = enum {
    @"inline",
    block,
    none,
};

pub const Specificity = struct {
    a: usize,
    b: usize,
    c: usize,

    pub fn order(self: Specificity, other: Specificity) std.math.Order {
        if (self.a == other.a) {
            if (self.b == other.b) {
                if (self.c == other.c) {
                    return .eq;
                } else if (self.c < other.c) {
                    return .lt;
                } else return .gt;
            } else if (self.b < other.b) {
                return .lt;
            } else return .gt;
        } else if (self.a < other.a) {
            return .lt;
        } else return .gt;
    }
};

pub const Rule = struct {
    selectors: []Selector,
    declarations: []Declaration,
};

pub const Selector = union(enum) {
    simple: Simple,

    pub const Simple = struct {
        tag_name: ?[]const u8,
        id: ?[]const u8,
        class: [][]const u8,
    };

    pub fn getSpecificity(self: *const Selector) Specificity {
        return switch (self.*) {
            .simple => .{
                .a = if (self.simple.id) |_| 1 else 0,
                .b = self.simple.class.len,
                .c = if (self.simple.tag_name) |_| 1 else 0,
            },
        };
    }
};

pub const Declaration = struct {
    property: []const u8,
    value: Value,
};

pub const Value = union(enum) {
    keyword: Keyword,
    length: Length,
    color: Color,

    pub const Length = struct {
        magnitude: f64,
        unit: Unit,

        pub const Unit = enum {
            px,
        };

        pub fn asPx(self: Length) ?f64 {
            return switch (self.unit) {
                .px => self.magnitude,
            };
        }
    };

    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    };

    // TODO: Make it an enum-string union, to speed up comparisons
    pub const Keyword = struct {
        name: []const u8,

        pub fn isKeyword(self: Keyword, name: []const u8) bool {
            return std.mem.eql(u8, self.name, name);
        }

        pub fn asStr(self: Keyword) []const u8 {
            return self.name;
        }

        pub fn fromStr(name: []const u8) Keyword {
            return .{ .name = name };
        }
    };

    pub fn isKeyword(self: Value, name: []const u8) bool {
        return switch (self) {
            .keyword => |keyword| keyword.isKeyword(name),
            else => false,
        };
    }

    pub fn asPx(self: Value) ?f64 {
        return switch (self) {
            .length => |length| length.asPx(),
            else => null,
        };
    }
};

rules: []Rule,

pub fn append(self: *Stylesheet, other: Stylesheet, allocator: std.mem.Allocator) void {
    var new = allocator.alloc(Rule, self.rules.len + other.rules.len) catch @panic("OOM");
    @memcpy(new[0..self.rules.len], self.rules);
    @memcpy(new[self.rules.len .. self.rules.len + other.rules.len], other.rules);
    self.rules = new;
}

pub fn print(self: *const Stylesheet) void {
    self.printIndent(0);
}

pub fn printIndent(self: *const Stylesheet, depth: usize) void {
    for (self.rules) |rule| {
        for (0..depth) |_| std.debug.print("  ", .{});

        for (rule.selectors) |selector| switch (selector) {
            .simple => std.debug.print("[tag_name={?s} id={?s} class={s}] ", .{ selector.simple.tag_name, selector.simple.id, selector.simple.class }),
        };
        std.debug.print("\n", .{});

        for (rule.declarations) |declaration| {
            for (0..depth + 1) |_| std.debug.print("  ", .{});
            std.debug.print("- {s}: ", .{declaration.property});
            switch (declaration.value) {
                .keyword => |keyword| std.debug.print("{s}", .{keyword.asStr()}),
                .length => |length| std.debug.print("{d} {s}", .{ length.magnitude, @tagName(length.unit) }),
                .color => |color| std.debug.print("#{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{ color.r, color.g, color.b, color.a }),
            }
            std.debug.print("\n", .{});
        }
    }
}

pub fn empty() Stylesheet {
    return .{
        .rules = &.{},
    };
}
