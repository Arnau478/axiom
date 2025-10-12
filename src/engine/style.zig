const std = @import("std");
const Dom = @import("Dom.zig");

pub const css = @import("style/css.zig");
pub const value = @import("style/value.zig");
pub const Stylesheet = @import("style/Stylesheet.zig");
pub const StyleTree = @import("style/StyleTree.zig");
pub const ComputedStyle = @import("style/ComputedStyle.zig");

pub fn style(allocator: std.mem.Allocator, dom: Dom, document_id: Dom.DocumentId, user_agent_stylesheet: ?Stylesheet) !StyleTree {
    var nodes: std.ArrayList(StyleTree.Node) = .empty;
    defer nodes.deinit(allocator);
    var computed_styles: std.ArrayList(ComputedStyle) = .empty;
    defer computed_styles.deinit(allocator);

    const root_element_id = dom.getDocument(document_id).?.element.?;

    var stylesheets: std.ArrayList(Stylesheet) = .empty;
    defer {
        for (stylesheets.items, 0..) |stylesheet, i| {
            if (user_agent_stylesheet != null and i == 0) continue;
            stylesheet.deinit(allocator);
        }
        stylesheets.deinit(allocator);
    }

    if (user_agent_stylesheet) |stylesheet| try stylesheets.append(allocator, stylesheet);

    var css_source_iter = dom.styleSourceIterator(document_id);
    while (css_source_iter.next()) |source| {
        try stylesheets.append(allocator, try css.parseStylesheet(allocator, source));
    }

    const root_style_node = try styleNode(allocator, &nodes, &computed_styles, dom, .{ .element = root_element_id }, stylesheets.items, null);

    return .{
        .allocator = allocator,
        .nodes = try nodes.toOwnedSlice(allocator),
        .computed_styles = try computed_styles.toOwnedSlice(allocator),
        .root = root_style_node.?,
    };
}

fn styleNode(
    allocator: std.mem.Allocator,
    nodes: *std.ArrayList(StyleTree.Node),
    computed_styles: *std.ArrayList(ComputedStyle),
    dom: Dom,
    dom_node: Dom.ContentNode,
    stylesheets: []const Stylesheet,
    parent_computed_style: ?ComputedStyle,
) !?StyleTree.NodeId {
    switch (dom_node) {
        .element => |element_id| {
            const raw_children = try allocator.alloc(StyleTree.NodeId, dom.getElement(element_id).?.children.items.len);
            errdefer allocator.free(raw_children);
            var children = raw_children;

            var computed_style = if (parent_computed_style) |parent| ComputedStyle.inheritedOrInitial(parent) else ComputedStyle.initial;

            for (stylesheets) |stylesheet| {
                var rules: std.ArrayList(Stylesheet.Rule.Style) = .empty;
                defer rules.deinit(allocator);

                for (stylesheet.rules) |rule| {
                    switch (rule) {
                        .style => |r| {
                            if (r.matches(dom, element_id)) {
                                try rules.append(allocator, r);
                            }
                        },
                    }
                }

                std.mem.sort(Stylesheet.Rule.Style, rules.items, {}, struct {
                    fn f(_: void, lhs: Stylesheet.Rule.Style, rhs: Stylesheet.Rule.Style) bool {
                        return lhs.specificity().order(rhs.specificity()) == .lt;
                    }
                }.f);

                for (rules.items) |rule| {
                    for (rule.declarations) |declaration| {
                        computed_style.applyDeclaration(declaration);
                    }
                }
            }

            if (dom.getElementAttribute(element_id, "style")) |inline_css| {
                const declarations = try css.parseDeclarationList(allocator, inline_css);
                defer allocator.free(declarations);

                for (declarations) |declaration| {
                    computed_style.applyDeclaration(declaration);
                }
            }

            computed_style.flush();

            try computed_styles.append(allocator, computed_style);

            const computed_style_id: StyleTree.ComputedStyleId = @enumFromInt(computed_styles.items.len - 1);

            var child_idx: usize = 0;
            for (dom.getElement(element_id).?.children.items) |dom_child| {
                if (try styleNode(allocator, nodes, computed_styles, dom, dom_child, stylesheets, computed_style)) |child| {
                    children[child_idx] = child;
                    child_idx += 1;
                }
            }
            children = try allocator.realloc(children, child_idx);

            try nodes.append(allocator, .{
                .dom_node = dom_node,
                .children = children,
                .computed_style = computed_style_id,
            });

            return @enumFromInt(nodes.items.len - 1);
        },
        .text => {
            const computed_style: ComputedStyle = .inheritedOrInitial(parent_computed_style.?);

            try computed_styles.append(allocator, computed_style);

            const computed_style_id: StyleTree.ComputedStyleId = @enumFromInt(computed_styles.items.len - 1);

            try nodes.append(allocator, .{
                .dom_node = dom_node,
                .computed_style = computed_style_id,
            });

            return @enumFromInt(nodes.items.len - 1);
        },
        .comment => return null,
    }
}
