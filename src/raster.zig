const std = @import("std");
const layout = @import("layout.zig");
const Stylesheet = @import("Stylesheet.zig");
const Rect = @import("Rect.zig");

const DisplayList = []DisplayCommand;

const DisplayCommand = union(enum) {
    solid_rect: struct {
        color: Stylesheet.Value.Color,
        rect: Rect,
    },

    pub fn format(self: DisplayCommand, _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}(", .{@tagName(self)});
        switch (self) {
            .solid_rect => |solid_rect| {
                try writer.print("x={d} y={d} w={d} h={d} color=#{x:0>2}{x:0>2}{x:0>2}", .{ solid_rect.rect.x, solid_rect.rect.y, solid_rect.rect.w, solid_rect.rect.h, solid_rect.color.r, solid_rect.color.g, solid_rect.color.b });
            },
        }
        try writer.print(")", .{});
    }
};

pub fn buildList(layout_root: layout.Box, allocator: std.mem.Allocator) !DisplayList {
    var list = std.ArrayList(DisplayCommand).init(allocator);

    try buildBox(&list, layout_root);

    return list.items;
}

fn buildBox(list: *std.ArrayList(DisplayCommand), box: layout.Box) !void {
    try buildBackground(list, box);
    try buildBorder(list, box);

    for (box.children) |child| {
        try buildBox(list, child);
    }
}

fn buildBackground(list: *std.ArrayList(DisplayCommand), box: layout.Box) !void {
    if (getColor(box, "background")) |color| {
        try list.append(.{ .solid_rect = .{ .color = color, .rect = box.dimensions.marginRect() } });
    }
}

fn buildBorder(list: *std.ArrayList(DisplayCommand), box: layout.Box) !void {
    const color = getColor(box, "border-color") orelse return;

    const d = &box.dimensions;
    const border_rect = box.dimensions.borderRect();

    try list.append(.{ .solid_rect = .{ .color = color, .rect = .{
        .x = border_rect.x,
        .y = border_rect.y,
        .w = d.border.left,
        .h = border_rect.h,
    } } });

    try list.append(.{ .solid_rect = .{ .color = color, .rect = .{
        .x = border_rect.x + border_rect.w - d.border.right,
        .y = border_rect.y,
        .w = d.border.right,
        .h = border_rect.h,
    } } });

    try list.append(.{ .solid_rect = .{ .color = color, .rect = .{
        .x = border_rect.x,
        .y = border_rect.y,
        .w = border_rect.w,
        .h = d.border.top,
    } } });

    try list.append(.{ .solid_rect = .{ .color = color, .rect = .{
        .x = border_rect.x,
        .y = border_rect.y + border_rect.h - d.border.bottom,
        .w = border_rect.w,
        .h = d.border.bottom,
    } } });
}

fn getColor(box: layout.Box, name: []const u8) ?Stylesheet.Value.Color {
    return switch (box.box_type) {
        .block_node, .inline_node => |node| switch (node.getProperty(name) orelse return null) {
            .color => |color| color,
            else => null,
        },
        .block_anon => null,
    };
}
