const std = @import("std");
const dom = @import("dom.zig");
const Stylesheet = @import("Stylesheet.zig");

pub const CascadeLevel = enum {
    agent,
    user_normal,
    author_normal,
    author_important,
    user_important,
};

pub fn styleDom(root: *dom.Node, allocator: std.mem.Allocator, agent_stylesheet: Stylesheet, user_stylesheet: Stylesheet) void {
    const author_stylesheet = root.getMixedStylesheet(allocator);
    styleNode(root, allocator, author_stylesheet, agent_stylesheet, user_stylesheet);
}

pub fn styleNode(node: *dom.Node, allocator: std.mem.Allocator, author_stylesheet: Stylesheet, agent_stylesheet: Stylesheet, user_stylesheet: Stylesheet) void {
    node.specified_properties = switch (node.node_type) {
        .text => Stylesheet.PropertyMap.init(allocator),
        .element => |element| prop_map: {
            const RuleSpecificityPair = struct {
                rule: Stylesheet.Rule,
                specificity: Stylesheet.Specificity,
                cascade_level: CascadeLevel,
            };
            var matched_rules = std.ArrayList(RuleSpecificityPair).init(allocator);

            for (author_stylesheet.rules) |rule| {
                blk: for (rule.selectors) |selector| {
                    if (element.matchesSelector(selector, allocator)) {
                        matched_rules.append(.{
                            .rule = rule,
                            .specificity = selector.getSpecificity(),
                            .cascade_level = .author_normal,
                        }) catch @panic("OOM");
                        break :blk;
                    }
                }
            }
            for (agent_stylesheet.rules) |rule| {
                blk: for (rule.selectors) |selector| {
                    if (element.matchesSelector(selector, allocator)) {
                        matched_rules.append(.{
                            .rule = rule,
                            .specificity = selector.getSpecificity(),
                            .cascade_level = .agent,
                        }) catch @panic("OOM");
                        break :blk;
                    }
                }
            }
            for (user_stylesheet.rules) |rule| {
                blk: for (rule.selectors) |selector| {
                    if (element.matchesSelector(selector, allocator)) {
                        matched_rules.append(.{
                            .rule = rule,
                            .specificity = selector.getSpecificity(),
                            .cascade_level = .user_normal,
                        }) catch @panic("OOM");
                        break :blk;
                    }
                }
            }

            // Sort matched rules by specificity, from least to most specific,
            // so that we can later apply then sequentially without worrying
            // about overwrites
            std.mem.sort(RuleSpecificityPair, matched_rules.items, .{}, struct {
                fn f(_: @TypeOf(.{}), sort_self: RuleSpecificityPair, sort_other: RuleSpecificityPair) bool {
                    if (sort_self.cascade_level == sort_other.cascade_level) {
                        return sort_self.specificity.order(sort_other.specificity) == .lt;
                    } else return @intFromEnum(sort_self.cascade_level) < @intFromEnum(sort_other.cascade_level);
                }
            }.f);

            // Apply the matched rules sequentially
            var prop_map = Stylesheet.PropertyMap.init(allocator);
            for (matched_rules.items) |pair| {
                for (pair.rule.declarations) |declaration| {
                    prop_map.put(declaration.property, declaration.value) catch @panic("OOM");
                }
            }
            break :prop_map prop_map;
        },
        .stylesheet => null,
    };
    for (node.children, 0..) |_, i| styleNode(&node.children[i], allocator, author_stylesheet, agent_stylesheet, user_stylesheet);
}
