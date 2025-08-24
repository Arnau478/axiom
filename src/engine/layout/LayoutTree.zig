const LayoutTree = @This();

const std = @import("std");
const style = @import("../style.zig");
const Box = @import("Box.zig");

pub const NodeId = enum(usize) { _ };

allocator: std.mem.Allocator,
nodes: std.ArrayListUnmanaged(Node),
root: NodeId,

pub const Node = struct {
    box: Box,
    children: std.ArrayListUnmanaged(NodeId) = .{},
    computed_style: *const style.ComputedStyle,
    style_node: ?style.StyleTree.NodeId,
};

pub fn getNode(tree: LayoutTree, id: NodeId) ?*Node {
    if (@intFromEnum(id) >= tree.nodes.items.len) return null;
    return &tree.nodes.items[@intFromEnum(id)];
}

fn addNode(tree: *LayoutTree, node: Node) !NodeId {
    try tree.nodes.append(tree.allocator, node);
    return @enumFromInt(tree.nodes.items.len - 1);
}

pub fn deinit(tree: *LayoutTree) void {
    for (tree.nodes.items) |*node| {
        node.children.deinit(tree.allocator);
    }

    tree.nodes.deinit(tree.allocator);
}

fn generateForNode(
    tree: *LayoutTree,
    style_tree: style.StyleTree,
    style_node: style.StyleTree.NodeId,
) !NodeId {
    std.log.debug("Generating layout tree for {}", .{style_tree.getNode(style_node).?.element});
    const computed_style = style_tree.getComputedStyle(style_tree.getNode(style_node).?.computed_style).?;

    std.debug.assert(computed_style.display != .none);

    const node = try tree.addNode(.{
        .box = undefined,
        .children = .{},
        .computed_style = computed_style,
        .style_node = style_node,
    });

    for (style_tree.getNode(style_node).?.children) |child| {
        const child_computed_style = style_tree.getComputedStyle(style_tree.getNode(child).?.computed_style).?;

        if (child_computed_style.display != .none) {
            const generated_child = try tree.generateForNode(style_tree, child);
            try tree.getNode(node).?.children.append(tree.allocator, generated_child);
        }
    }

    return node;
}

pub fn generate(
    allocator: std.mem.Allocator,
    style_tree: style.StyleTree,
) !LayoutTree {
    var tree: LayoutTree = .{
        .allocator = allocator,
        .nodes = .{},
        .root = undefined,
    };
    tree.root = try tree.generateForNode(style_tree, style_tree.root);
    return tree;
}
