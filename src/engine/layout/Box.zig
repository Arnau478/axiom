const Box = @This();

const std = @import("std");
const Dom = @import("../Dom.zig");
const style = @import("../style.zig");
const layout = @import("../layout.zig");
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

pub fn printTree(box: *const Box, dom: Dom, writer: std.io.AnyWriter) !void {
    try box.printTreeWithDepth(dom, writer, 0);
}

fn printTreeWithDepth(box: *const Box, dom: Dom, writer: std.io.AnyWriter, depth: usize) !void {
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
