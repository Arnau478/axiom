const Stylesheet = @This();

const std = @import("std");
const css = @import("css.zig");
const value = @import("value.zig");

rules: []const Rule,

pub const Rule = union(enum) {
    style: Style,

    pub const Style = struct {
        selectors: []const Selector,
        declarations: []const Declaration,

        pub const Selector = union(enum) {
            simple: Simple,

            pub const Simple = struct {
                element_name: ?[]const u8,
                id: ?[]const u8,
                class: []const []const u8,

                pub fn specificity(selector: Simple) Specificity {
                    return .{
                        .a = if (selector.id) |_| 1 else 0,
                        .b = selector.class.len,
                        .c = if (selector.element_name) |_| 1 else 0,
                    };
                }
            };

            pub fn specificity(selector: Selector) Specificity {
                return switch (selector) {
                    inline else => |s| s.specificity(),
                };
            }
        };

        pub const Declaration = union(Property) {
            // TODO: Generate this at comptime
            @"margin-top": Property.@"margin-top".Value(),
            @"margin-right": Property.@"margin-right".Value(),
            @"margin-bottom": Property.@"margin-bottom".Value(),
            @"margin-left": Property.@"margin-left".Value(),

            pub const Property = enum {
                @"margin-top",
                @"margin-right",
                @"margin-bottom",
                @"margin-left",

                pub fn byName(name: []const u8) ?Property {
                    for (std.enums.values(Property)) |v| {
                        if (std.ascii.eqlIgnoreCase(name, @tagName(v))) {
                            return v;
                        }
                    } else {
                        return null;
                    }
                }

                pub fn Value(comptime property: Property) type {
                    return switch (property) {
                        .@"margin-top", .@"margin-right", .@"margin-bottom", .@"margin-left" => struct {
                            value: union(enum) {
                                length_percentage: value.LengthPercentage,
                                // TODO: "auto" keyword
                            },
                        },
                    };
                }
            };
        };

        pub const Specificity = struct {
            a: usize,
            b: usize,
            c: usize,

            pub fn order(lhs: Specificity, rhs: Specificity) std.math.Order {
                if (lhs.a < rhs.a) return .lt;
                if (lhs.a > rhs.a) return .gt;
                if (lhs.b < rhs.b) return .lt;
                if (lhs.b > rhs.b) return .gt;
                if (lhs.c < rhs.c) return .lt;
                if (lhs.c > rhs.c) return .gt;

                return .eq;
            }

            pub fn add(lhs: Specificity, rhs: Specificity) Specificity {
                return .{
                    .a = lhs.a + rhs.a,
                    .b = lhs.b + rhs.b,
                    .c = lhs.c + rhs.c,
                };
            }

            pub const zero: Specificity = .{ .a = 0, .b = 0, .c = 0 };
        };

        pub fn specificity(rule: Style) Specificity {
            var res: Specificity = .zero;

            for (rule.selectors) |selector| {
                res = res.add(selector.specificity());
            }

            return res;
        }
    };
};
