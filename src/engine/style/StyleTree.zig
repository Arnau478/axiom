const StyleTree = @This();

const std = @import("std");
const Dom = @import("../Dom.zig");
const ComputedStyle = @import("ComputedStyle.zig");

pub const NodeId = enum(usize) { _ };
pub const ComputedStyleId = enum(usize) { _ };

pub const Node = struct {
    element: Dom.ElementId,
    computed_style: ComputedStyleId,
    children: []const NodeId = &.{},

    fn deinit(node: Node, allocator: std.mem.Allocator) void {
        allocator.free(node.children);
    }
};

allocator: std.mem.Allocator,
nodes: []Node,
computed_styles: []ComputedStyle,
root: NodeId,

pub fn deinit(tree: StyleTree) void {
    for (tree.nodes) |node| {
        node.deinit(tree.allocator);
    }

    tree.allocator.free(tree.nodes);
    tree.allocator.free(tree.computed_styles);
}

pub fn getNode(tree: StyleTree, id: NodeId) ?*Node {
    if (@intFromEnum(id) > tree.nodes.len) return null;
    return &tree.nodes[@intFromEnum(id)];
}

pub fn getComputedStyle(tree: StyleTree, id: ComputedStyleId) ?*ComputedStyle {
    if (@intFromEnum(id) > tree.computed_styles.len) return null;
    return &tree.computed_styles[@intFromEnum(id)];
}
