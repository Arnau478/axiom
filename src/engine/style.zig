const std = @import("std");
const Dom = @import("Dom.zig");

pub const css = @import("style/css.zig");
pub const value = @import("style/value.zig");
pub const Stylesheet = @import("style/Stylesheet.zig");
pub const StyleTree = @import("style/StyleTree.zig");
pub const ComputedStyle = @import("style/ComputedStyle.zig");

pub fn style(allocator: std.mem.Allocator, dom: Dom, document_id: Dom.DocumentId, user_agent_stylesheet: ?Stylesheet) !StyleTree {
    var nodes = std.ArrayList(StyleTree.Node).init(allocator);
    defer nodes.deinit();
    var computed_styles = std.ArrayList(ComputedStyle).init(allocator);
    defer computed_styles.deinit();

    const root_element_id = dom.getDocument(document_id).?.element.?;

    var stylesheets = std.ArrayList(Stylesheet).init(allocator);
    defer {
        for (stylesheets.items, 0..) |stylesheet, i| {
            if (user_agent_stylesheet != null and i == 0) continue;
            stylesheet.deinit(allocator);
        }
        stylesheets.deinit();
    }

    if (user_agent_stylesheet) |stylesheet| try stylesheets.append(stylesheet);

    var css_source_iter = dom.styleSourceIterator(document_id);
    while (css_source_iter.next()) |source| {
        try stylesheets.append(try css.parseStylesheet(allocator, source));
    }

    const root_style_node = try styleElement(allocator, &nodes, &computed_styles, dom, root_element_id, stylesheets.items, null);

    return .{
        .allocator = allocator,
        .nodes = try nodes.toOwnedSlice(),
        .computed_styles = try computed_styles.toOwnedSlice(),
        .root = root_style_node,
    };
}

fn styleElement(
    allocator: std.mem.Allocator,
    nodes: *std.ArrayList(StyleTree.Node),
    computed_styles: *std.ArrayList(ComputedStyle),
    dom: Dom,
    element_id: Dom.ElementId,
    stylesheets: []const Stylesheet,
    parent_computed_style: ?ComputedStyle,
) !StyleTree.NodeId {
    const raw_children = try allocator.alloc(StyleTree.NodeId, dom.getElement(element_id).?.children.items.len);
    errdefer allocator.free(raw_children);
    var children = raw_children;

    var computed_style = if (parent_computed_style) |parent| ComputedStyle.inheritedOrInitial(parent) else ComputedStyle.initial;

    for (stylesheets) |stylesheet| {
        var rules = std.ArrayList(Stylesheet.Rule.Style).init(allocator);
        defer rules.deinit();

        for (stylesheet.rules) |rule| {
            switch (rule) {
                .style => |r| {
                    if (r.matches(dom, element_id)) {
                        try rules.append(r);
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

    try computed_styles.append(computed_style);

    const computed_style_id: StyleTree.ComputedStyleId = @enumFromInt(computed_styles.items.len - 1);

    var child_idx: usize = 0;
    for (dom.getElement(element_id).?.children.items) |dom_child| {
        switch (dom_child) {
            .element => {
                children[child_idx] = try styleElement(allocator, nodes, computed_styles, dom, dom_child.element, stylesheets, computed_style);
                child_idx += 1;
            },
            .text, .comment => {},
        }
    }
    children = try allocator.realloc(children, child_idx);

    try nodes.append(.{
        .element = element_id,
        .children = children,
        .computed_style = computed_style_id,
    });

    return @enumFromInt(nodes.items.len - 1);
}
