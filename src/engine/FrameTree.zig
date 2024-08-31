const FrameTree = @This();

const std = @import("std");
const engine = @import("engine.zig");

allocator: std.mem.Allocator,
root: Node,

pub const Node = struct {
    type: Type,
    children: std.ArrayListUnmanaged(Node) = .{},

    pub const Type = union(enum) {
        viewport: Viewport,
        box: Box,

        pub const Viewport = struct {
            size: engine.Size,
        };

        pub const Box = struct {
            type: Box.Type,
            box_model: engine.layout.BoxModel,

            pub const Type = union(enum) {
                block,
            };
        };
    };

    pub fn appendChild(node: *Node, tree: *const FrameTree, child: Node) !*Node {
        try node.children.append(tree.allocator, child);

        return &node.children.items[node.children.items.len - 1];
    }

    pub fn deinit(node: *Node, allocator: std.mem.Allocator) void {
        for (node.children.items) |*child| {
            child.deinit(allocator);
        }

        node.children.deinit(allocator);
    }
};

pub fn deinit(tree: *FrameTree) void {
    tree.root.deinit(tree.allocator);
}
