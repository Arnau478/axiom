const Stylesheet = @This();

const std = @import("std");
const css = @import("css.zig");
const value = @import("value.zig");
const layout = @import("../layout.zig");
const Dom = @import("../Dom.zig");

rules: []const Rule,

pub const Rule = union(enum) {
    style: Style,

    pub const Style = struct {
        selectors: []const Selector,
        declarations: []const Declaration,

        pub const Selector = union(enum) {
            simple: Simple,

            pub const Simple = struct {
                tag_name: ?[]const u8,
                id: ?[]const u8,
                class: []const []const u8,

                pub fn specificity(selector: Simple) Specificity {
                    return .{
                        .a = if (selector.id) |_| 1 else 0,
                        .b = selector.class.len,
                        .c = if (selector.tag_name) |_| 1 else 0,
                    };
                }

                pub fn matches(selector: Simple, dom: Dom, element: Dom.ElementId) bool {
                    if (selector.tag_name) |name| {
                        if (!std.mem.eql(u8, dom.getElement(element).?.tag_name, name)) return false;
                    }

                    // TODO: Class
                    // TODO: ID

                    return true;
                }
            };

            pub fn specificity(selector: Selector) Specificity {
                return switch (selector) {
                    inline else => |s| s.specificity(),
                };
            }

            pub fn matches(selector: Selector, dom: Dom, element: Dom.ElementId) bool {
                return switch (selector) {
                    inline else => |s| s.matches(dom, element),
                };
            }
        };

        pub const Declaration = union(Property) {
            // TODO: Generate this at comptime
            margin: Property.margin.Value(),
            @"margin-top": Property.@"margin-top".Value(),
            @"margin-right": Property.@"margin-right".Value(),
            @"margin-bottom": Property.@"margin-bottom".Value(),
            @"margin-left": Property.@"margin-left".Value(),
            @"border-top-width": Property.@"border-top-width".Value(),
            @"border-right-width": Property.@"border-right-width".Value(),
            @"border-bottom-width": Property.@"border-bottom-width".Value(),
            @"border-left-width": Property.@"border-left-width".Value(),
            @"padding-top": Property.@"padding-top".Value(),
            @"padding-right": Property.@"padding-right".Value(),
            @"padding-bottom": Property.@"padding-bottom".Value(),
            @"padding-left": Property.@"padding-left".Value(),
            width: Property.width.Value(),
            height: Property.height.Value(),
            display: Property.display.Value(),
            position: Property.position.Value(),
            @"background-color": Property.@"background-color".Value(),

            pub const Property = enum {
                margin,
                @"margin-top",
                @"margin-right",
                @"margin-bottom",
                @"margin-left",

                @"border-top-width",
                @"border-right-width",
                @"border-bottom-width",
                @"border-left-width",

                @"padding-top",
                @"padding-right",
                @"padding-bottom",
                @"padding-left",

                width,
                height,

                display,
                position,

                @"background-color",

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
                        .margin => struct {
                            value: union(enum) {
                                one: Value(.@"margin-top"),
                                two: struct {
                                    a: Value(.@"margin-top"),
                                    b: Value(.@"margin-top"),
                                },
                                three: struct {
                                    a: Value(.@"margin-top"),
                                    b: Value(.@"margin-top"),
                                    c: Value(.@"margin-top"),
                                },
                                four: struct {
                                    a: Value(.@"margin-top"),
                                    b: Value(.@"margin-top"),
                                    c: Value(.@"margin-top"),
                                    d: Value(.@"margin-top"),
                                },
                            },
                        },
                        .@"margin-top", .@"margin-right", .@"margin-bottom", .@"margin-left" => struct {
                            value: union(enum) {
                                length_percentage: value.LengthPercentage,
                                auto,
                            },
                        },
                        .@"border-top-width", .@"border-right-width", .@"border-bottom-width", .@"border-left-width" => struct {
                            value: union(enum) {
                                length: value.Length,
                                thin,
                                medium,
                                thick,
                            },
                        },
                        .@"padding-top", .@"padding-right", .@"padding-bottom", .@"padding-left" => struct {
                            value: value.LengthPercentage,
                        },
                        .width, .height => struct {
                            value: union(enum) {
                                length_percentage: value.LengthPercentage,
                                auto,
                            },
                        },
                        .display => struct {
                            value: enum {
                                @"inline",
                                block,
                                @"list-item",
                                @"inline-block",
                                table,
                                @"inline-table",
                                @"table-row_group",
                                @"table-header_group",
                                @"table-footer_group",
                                @"table-row",
                                @"table-column_group",
                                @"table-column",
                                @"table-cell",
                                @"table-caption",
                                none,
                            },
                        },
                        .position => struct {
                            value: layout.Position,
                        },
                        .@"background-color" => struct {
                            value: value.Color,
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

        pub fn matches(rule: Style, dom: Dom, element: Dom.ElementId) bool {
            for (rule.selectors) |selector| {
                if (selector.matches(dom, element)) return true;
            }

            return false;
        }
    };
};

pub fn deinit(stylesheet: Stylesheet, allocator: std.mem.Allocator) void {
    for (stylesheet.rules) |rule| {
        switch (rule) {
            .style => |r| {
                allocator.free(r.selectors);
                allocator.free(r.declarations);
            },
        }
    }

    allocator.free(stylesheet.rules);
}
