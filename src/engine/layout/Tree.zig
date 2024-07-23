const std = @import("std");

const Style = @import("Style.zig");

const Tree = @This();

allocator: std.mem.Allocator,
root: ?*Node,

pub const Node = struct {
    style: Style,
    children: std.ArrayListUnmanaged(Node),

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        self.children.deinit(allocator);
    }
};

pub fn deinit(self: Tree) void {
    if (self.root) |root| {
        root.deinit(self.allocator);
        self.allocator.destroy(root);
    }
}
