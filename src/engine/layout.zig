const std = @import("std");
const style = @import("style.zig");

pub const Point = @import("layout/Point.zig");
pub const Size = @import("layout/Size.zig");
pub const EdgeSizes = @import("layout/EdgeSizes.zig");
pub const Rect = @import("layout/Rect.zig");
pub const Box = @import("layout/Box.zig");
pub const LayoutTree = @import("layout/LayoutTree.zig");

pub const Display = enum {
    @"inline",
    block,
    inline_block,
    none,
};

pub const FormattingContext = union(enum) {
    block: Block,

    pub const Block = @import("layout/FormattingContext/Block.zig");

    pub fn create(display: Display) FormattingContext {
        return switch (display) {
            .block, .inline_block => .{
                .block = .init(),
            },
            .@"inline" => @panic("TODO"),
            .none => unreachable,
        };
    }

    pub fn layout(ctx: FormattingContext, tree: LayoutTree, node_id: LayoutTree.NodeId, containing_rect: Rect) void {
        switch (ctx) {
            inline else => |c| c.layout(tree, node_id, containing_rect),
        }
    }
};

pub fn reflow(tree: LayoutTree, viewport_width: f32) void {
    const root = tree.getNode(tree.root).?;
    const root_ctx = FormattingContext.create(root.computed_style.display);

    root_ctx.layout(tree, tree.root, .{
        .origin = .zero,
        .size = .{ .width = viewport_width, .height = 0 },
    });
}
