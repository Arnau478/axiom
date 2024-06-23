const std = @import("std");
const Specificity = @import("Specificity.zig");

const Stylesheet = @This();

location: ?[]const u8,
value: []const Rule,

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
        };

        pub fn specificity(self: Selector) Specificity {
            return switch (self) {
                inline else => |s| s.specificity(),
            };
        }
    };

    pub const Declaration = struct {
        property: []const u8,
        value: Value,
    };

    pub fn specificity(self: Rule) Specificity {
        var spec = Specificity{ .a = 0, .b = 0, .c = 0 };

        for (self.selectors) |sel| {
            spec = spec.add(sel.specificity());
        }

        return spec;
    }
};

pub const Value = union(enum) {
    color: Color,

    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    };
};
