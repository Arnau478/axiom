const std = @import("std");
const Dom = @import("Dom.zig");

pub const css = @import("style/css.zig");
pub const value = @import("style/value.zig");
pub const Stylesheet = @import("style/Stylesheet.zig");
pub const StyleTree = @import("style/StyleTree.zig");
pub const ComputedStyle = @import("style/ComputedStyle.zig");

pub fn style(allocator: std.mem.Allocator, dom: Dom, document_id: Dom.DocumentId) !StyleTree {
    var nodes = std.ArrayList(StyleTree.Node).init(allocator);
    var computed_styles = std.ArrayList(ComputedStyle).init(allocator);
    const root_element_id = dom.getDocument(document_id).?.element.?;
    const root_style_node = try styleElement(allocator, &nodes, &computed_styles, dom, root_element_id);

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
) !StyleTree.NodeId {
    const raw_children = try allocator.alloc(StyleTree.NodeId, dom.getElement(element_id).?.children.items.len);
    errdefer allocator.free(raw_children);
    var children = raw_children;

    var computed_style: ComputedStyle = .{};

    if (dom.getElementAttribute(element_id, "style")) |inline_css| {
        const declarations = try css.parseDeclarationList(allocator, inline_css);
        defer allocator.free(declarations);

        for (declarations) |declaration| {
            applyDeclaration(declaration, &computed_style);
        }
    }

    try computed_styles.append(computed_style);
    const computed_style_id: StyleTree.ComputedStyleId = @enumFromInt(computed_styles.items.len - 1);

    var child_idx: usize = 0;
    for (dom.getElement(element_id).?.children.items) |dom_child| {
        switch (dom_child) {
            .element => {
                children[child_idx] = try styleElement(allocator, nodes, computed_styles, dom, dom_child.element);
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

fn applyDeclaration(declaration: Stylesheet.Rule.Style.Declaration, computed_style: *ComputedStyle) void {
    switch (declaration) {
        .@"margin-top" => |v| computed_style.margin_top = v,
        .@"margin-right" => |v| computed_style.margin_right = v,
        .@"margin-bottom" => |v| computed_style.margin_bottom = v,
        .@"margin-left" => |v| computed_style.margin_left = v,
        .display => |v| computed_style.display = v,
    }
}
