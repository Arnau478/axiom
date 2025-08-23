const std = @import("std");
const Point = @import("Point.zig");
const Size = @import("Size.zig");
const Rect = @import("Rect.zig");
const EdgeSizes = @import("EdgeSizes.zig");
const LayoutTree = @import("LayoutTree.zig");

pub const Display = enum {
    block,
    @"inline",
    inline_block,
};

pub const Position = enum {
    static,
    absolute,
    relative,
    fixed,
};

pub fn reflow(tree: LayoutTree, viewport_width: f32) void {
    reflowNode(tree, tree.root, .{ .origin = .zero, .size = .{ .width = viewport_width, .height = 0 } });
}

fn reflowNode(tree: LayoutTree, id: LayoutTree.NodeId, containing_rect: Rect) void {
    std.debug.assert(containing_rect.size.height == 0);

    const node = tree.getNode(id).?;

    calculateContentWidth(node, containing_rect.size);

    positionNode(node, containing_rect);

    reflowChildren(node, tree);

    finalizeNodeDimensions(node);
}

fn calculateContentWidth(node: *LayoutTree.Node, containing_size: Size) void {
    var width = switch (node.computed_style.width.value) {
        .length_percentage => |length_percentage| switch (length_percentage) {
            .length => |length| length.toPx(),
            .percentage => |percentage| percentage.of(containing_size.width),
        },
        .auto => null,
    };

    var margin_left = switch (node.computed_style.margin_left.value) {
        .length_percentage => |length_percentage| switch (length_percentage) {
            .length => |length| length.toPx(),
            .percentage => |percentage| percentage.of(containing_size.width),
        },
        .auto => null,
    };
    var margin_right = switch (node.computed_style.margin_right.value) {
        .length_percentage => |length_percentage| switch (length_percentage) {
            .length => |length| length.toPx(),
            .percentage => |percentage| percentage.of(containing_size.width),
        },
        .auto => null,
    };

    const border_left = node.computed_style.border_left_width.toPx();
    const border_right = node.computed_style.border_right_width.toPx();

    const padding_left = switch (node.computed_style.padding_left.value) {
        .length => |length| length.toPx(),
        .percentage => |percentage| percentage.of(containing_size.width),
    };
    const padding_right = switch (node.computed_style.padding_right.value) {
        .length => |length| length.toPx(),
        .percentage => |percentage| percentage.of(containing_size.width),
    };

    const total = (width orelse 0) + (margin_left orelse 0) + (margin_right orelse 0) +
        border_left + border_right + padding_left + padding_right;

    if (width != null and total > containing_size.width) {
        margin_left = margin_left orelse 0;
        margin_right = margin_right orelse 0;
    }

    const underflow = containing_size.width - total;

    if (width != null) {
        if (margin_left != null and margin_right != null) {
            margin_right.? += underflow;
        } else if (margin_left != null and margin_right == null) {
            margin_right = underflow;
        } else if (margin_left == null and margin_right != null) {
            margin_left = underflow;
        } else {
            margin_left = underflow / 2;
            margin_right = underflow / 2;
        }
    } else {
        margin_left = margin_left orelse 0;
        margin_right = margin_right orelse 0;

        if (underflow >= 0) {
            width = underflow;
        } else {
            width = 0;
            margin_right.? += underflow;
        }
    }

    std.debug.assert(width != null);
    std.debug.assert(margin_left != null);
    std.debug.assert(margin_right != null);

    node.box = .{
        .content_box = .{
            .origin = undefined,
            .size = .{
                .width = width.?,
                .height = 0,
            },
        },
        .margin = .{
            .top = undefined,
            .right = margin_right.?,
            .bottom = undefined,
            .left = margin_left.?,
        },
        .border = .{
            .top = undefined,
            .right = border_right,
            .bottom = undefined,
            .left = border_left,
        },
        .padding = .{
            .top = undefined,
            .right = padding_right,
            .bottom = undefined,
            .left = padding_left,
        },
    };
}

fn positionNode(node: *LayoutTree.Node, containing_rect: Rect) void {
    node.box.margin.top = switch (node.computed_style.margin_top.value) {
        .length_percentage => |length_percentage| switch (length_percentage) {
            .length => |length| length.toPx(),
            .percentage => |percentage| percentage.of(containing_rect.size.width),
        },
        .auto => 0,
    };
    node.box.margin.bottom = switch (node.computed_style.margin_bottom.value) {
        .length_percentage => |length_percentage| switch (length_percentage) {
            .length => |length| length.toPx(),
            .percentage => |percentage| percentage.of(containing_rect.size.width),
        },
        .auto => 0,
    };

    node.box.border.top = node.computed_style.border_top_width.toPx();
    node.box.border.bottom = node.computed_style.border_bottom_width.toPx();

    node.box.padding.top = switch (node.computed_style.padding_top.value) {
        .length => |length| length.toPx(),
        .percentage => |percentage| percentage.of(containing_rect.size.width),
    };
    node.box.padding.bottom = switch (node.computed_style.padding_bottom.value) {
        .length => |length| length.toPx(),
        .percentage => |percentage| percentage.of(containing_rect.size.width),
    };

    node.box.content_box.origin = .{
        .x = containing_rect.origin.x + node.box.margin.left + node.box.border.left + node.box.padding.left,
        .y = containing_rect.origin.y + containing_rect.size.height + node.box.margin.top + node.box.border.top + node.box.padding.top,
    };
}

fn reflowChildren(node: *LayoutTree.Node, tree: LayoutTree) void {
    for (node.children.items) |child| {
        reflowNode(tree, child, node.box.content_box);
        node.box.content_box.size.height += tree.getNode(child).?.box.marginBox().size.height;
    }
}

fn finalizeNodeDimensions(node: *LayoutTree.Node) void {
    node.box.content_box.size.height = switch (node.computed_style.height.value) {
        .length_percentage => |length_percentage| switch (length_percentage) {
            .length => |length| length.toPx(),
            .percentage => @panic("TODO"),
        },
        .auto => node.box.content_box.size.height,
    };
}
