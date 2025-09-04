const Box = @This();

const std = @import("std");
const Dom = @import("../Dom.zig");
const style = @import("../style.zig");
const layout = @import("../layout.zig");
const Size = @import("Size.zig");
const Rect = @import("Rect.zig");
const BoxModel = @import("BoxModel.zig");

children: std.ArrayListUnmanaged(*Box),
parent: ?*Box,
computed_style: style.ComputedStyle,
element: ?Dom.ElementId,
box_model: BoxModel,

pub fn init(allocator: std.mem.Allocator, computed_style: style.ComputedStyle, element: ?Dom.ElementId) !*Box {
    const box = try allocator.create(Box);
    errdefer allocator.destroy(box);

    box.* = .{
        .children = .empty,
        .parent = null,
        .computed_style = computed_style,
        .element = element,
        .box_model = .{
            .content_box = .{
                .origin = .zero,
                .size = .zero,
            },
            .padding = .zero,
            .border = .zero,
            .margin = .zero,
        },
    };

    return box;
}

pub fn deinit(box: *Box, allocator: std.mem.Allocator) void {
    for (box.children.items) |child| {
        child.deinit(allocator);
    }
    box.children.deinit(allocator);
    allocator.destroy(box);
}

pub fn appendChild(parent: *Box, allocator: std.mem.Allocator, child: *Box) !void {
    child.parent = parent;
    try parent.children.append(allocator, child);
}

pub fn boxLevel(box: Box) layout.BoxLevel {
    return box.computed_style.display.boxLevel();
}

pub fn containerType(box: Box) layout.ContainerBoxType {
    return box.computed_style.display.containerType();
}

pub fn positioningScheme(box: Box) layout.PositioningScheme {
    return box.computed_style.position.positioningScheme();
}

pub fn predetermineDimensions(box: *Box, containing_block: Rect) void {
    var width = if (box.computed_style.width) |width| switch (width) {
        .length => |length| length.toPx(),
        .percentage => |percentage| percentage.of(containing_block.size.width),
    } else null;

    var margin_left = switch (box.computed_style.margin_left) {
        .length_percentage => |length_percentage| switch (length_percentage) {
            .length => |length| length.toPx(),
            .percentage => |percentage| percentage.of(containing_block.size.width),
        },
        .auto => null,
    };
    var margin_right = switch (box.computed_style.margin_right) {
        .length_percentage => |length_percentage| switch (length_percentage) {
            .length => |length| length.toPx(),
            .percentage => |percentage| percentage.of(containing_block.size.width),
        },
        .auto => null,
    };

    const margin_top = switch (box.computed_style.margin_top) {
        .length_percentage => |length_percentage| switch (length_percentage) {
            .length => |length| length.toPx(),
            .percentage => |percentage| percentage.of(containing_block.size.width),
        },
        .auto => null,
    };
    const margin_bottom = switch (box.computed_style.margin_bottom) {
        .length_percentage => |length_percentage| switch (length_percentage) {
            .length => |length| length.toPx(),
            .percentage => |percentage| percentage.of(containing_block.size.width),
        },
        .auto => null,
    };

    const border_left = box.computed_style.border_left_width.toPx();
    const border_right = box.computed_style.border_right_width.toPx();

    const border_top = box.computed_style.border_top_width.toPx();
    const border_bottom = box.computed_style.border_bottom_width.toPx();

    const padding_left = switch (box.computed_style.padding_left) {
        .length => |length| length.toPx(),
        .percentage => |percentage| percentage.of(containing_block.size.width),
    };
    const padding_right = switch (box.computed_style.padding_right) {
        .length => |length| length.toPx(),
        .percentage => |percentage| percentage.of(containing_block.size.width),
    };

    const padding_top = switch (box.computed_style.padding_top) {
        .length => |length| length.toPx(),
        .percentage => |percentage| percentage.of(containing_block.size.width),
    };
    const padding_bottom = switch (box.computed_style.padding_bottom) {
        .length => |length| length.toPx(),
        .percentage => |percentage| percentage.of(containing_block.size.width),
    };

    if (box.boxLevel() == .block and box.positioningScheme() == .normal_flow) {
        // TODO: Replaced elements

        const total = (margin_left orelse 0) + border_left + padding_left + (width orelse 0) + padding_right + border_right + (margin_right orelse 0);

        if (width != null and total > containing_block.size.width) {
            margin_left = margin_left orelse 0;
            margin_right = margin_right orelse 0;
        }

        const underflow = containing_block.size.width - total;

        if (width != null and margin_left != null and margin_right != null) {
            // TODO: Direction

            margin_right.? += underflow;
        }

        if (width != null and margin_left == null and margin_right != null) margin_left = underflow;
        if (width != null and margin_left != null and margin_right == null) margin_right = underflow;

        if (width == null) {
            margin_left = margin_left orelse 0;
            margin_right = margin_right orelse 0;

            if (underflow > 0) {
                width = underflow;
            } else {
                width = 0;
                margin_right.? += underflow;
            }
        }

        if (margin_left == null and margin_right == null) {
            std.debug.assert(width != null);

            margin_left = underflow / 2;
            margin_right = underflow / 2;
        }
    } else {
        @panic("TODO");
    }

    std.debug.assert(width != null);
    std.debug.assert(margin_left != null);
    std.debug.assert(margin_right != null);

    box.box_model = .{
        .content_box = .{
            .origin = box.box_model.content_box.origin,
            .size = .{ .width = width.?, .height = box.box_model.content_box.size.height },
        },
        .margin = .{
            .top = margin_top orelse 0,
            .right = margin_right.?,
            .bottom = margin_bottom orelse 0,
            .left = margin_left.?,
        },
        .border = .{
            .top = border_top,
            .right = border_right,
            .bottom = border_bottom,
            .left = border_left,
        },
        .padding = .{
            .top = padding_top,
            .right = padding_right,
            .bottom = padding_bottom,
            .left = padding_left,
        },
    };
}

pub fn predeterminePosition(box: *Box, containing_block: Rect) void {
    switch (box.boxLevel()) {
        .block => {
            box.box_model.content_box.origin = .{
                .x = containing_block.origin.x +
                    box.box_model.padding.left +
                    box.box_model.border.left +
                    box.box_model.margin.left,
                .y = containing_block.origin.y +
                    box.box_model.padding.top +
                    box.box_model.border.top +
                    box.box_model.margin.top,
            };
        },
        .@"inline" => @panic("TODO"),
    }
}

pub fn finalizeDimensions(box: *Box, containing_block: Rect) void {
    const height = if (box.computed_style.height) |height| switch (height) {
        .length => |length| length.toPx(),
        .percentage => |percentage| percentage.of(containing_block.size.width),
    } else null;

    if (height) |h| box.box_model.content_box.size.height = h;
}

pub fn printTree(box: *const Box, dom: Dom, writer: *std.Io.Writer) !void {
    try box.printTreeWithDepth(dom, writer, 0);
    try writer.flush();
}

fn printTreeWithDepth(box: *const Box, dom: Dom, writer: *std.Io.Writer, depth: usize) !void {
    for (0..depth) |_| try writer.writeAll("  ");

    if (box.element) |element_id| {
        const element = dom.getElement(element_id).?;
        try writer.print("<{s}>", .{element.tag_name});
    } else {
        try writer.writeAll("(anon)");
    }
    try writer.writeAll(": ");

    try writer.print("{s}-level, {s} container", .{
        @tagName(box.computed_style.display.boxLevel()),
        @tagName(box.computed_style.display.containerType()),
    });

    try writer.writeByte('\n');

    for (box.children.items) |child| {
        try child.printTreeWithDepth(dom, writer, depth + 1);
    }
}
