const std = @import("std");
const build_options = @import("build_options");
const layout = @import("layout.zig");
const render = @import("render.zig");

pub fn paint(allocator: std.mem.Allocator, layout_tree: layout.LayoutTree) ![]const render.Command {
    var commands = std.ArrayList(render.Command).init(allocator);
    defer commands.deinit();

    try paintNode(layout_tree, layout_tree.root, &commands);

    return try commands.toOwnedSlice();
}

fn paintNode(layout_tree: layout.LayoutTree, id: layout.LayoutTree.NodeId, commands: *std.ArrayList(render.Command)) !void {
    const node = layout_tree.getNode(id).?;

    if (node.computed_style.background_color.value.a != 0) {
        std.debug.assert(node.computed_style.background_color.value.a == 255); // TODO: Transparency

        try commands.append(.{ .simple_rect = .{
            .x = @intFromFloat(node.box.borderBox().origin.x),
            .y = @intFromFloat(node.box.borderBox().origin.y),
            .width = @intFromFloat(node.box.borderBox().size.width),
            .height = @intFromFloat(node.box.borderBox().size.height),
            .color = .{
                .r = node.computed_style.background_color.value.r,
                .g = node.computed_style.background_color.value.g,
                .b = node.computed_style.background_color.value.b,
            },
        } });
    }

    // TODO: Borders

    // TODO: Text

    if (build_options.paint_box_model) {
        try commands.append(.{ .simple_rect = .{
            .x = @intFromFloat(node.box.marginBox().origin.x),
            .y = @intFromFloat(node.box.marginBox().origin.y),
            .width = @intFromFloat(node.box.marginBox().size.width),
            .height = @intFromFloat(node.box.marginBox().size.height),
            .color = .{ .r = 100, .g = 0, .b = 200 },
        } });
        try commands.append(.{ .simple_rect = .{
            .x = @intFromFloat(node.box.borderBox().origin.x),
            .y = @intFromFloat(node.box.borderBox().origin.y),
            .width = @intFromFloat(node.box.borderBox().size.width),
            .height = @intFromFloat(node.box.borderBox().size.height),
            .color = .{ .r = 100, .g = 100, .b = 100 },
        } });
        try commands.append(.{ .simple_rect = .{
            .x = @intFromFloat(node.box.paddingBox().origin.x),
            .y = @intFromFloat(node.box.paddingBox().origin.y),
            .width = @intFromFloat(node.box.paddingBox().size.width),
            .height = @intFromFloat(node.box.paddingBox().size.height),
            .color = .{ .r = 0, .g = 200, .b = 100 },
        } });
        try commands.append(.{ .simple_rect = .{
            .x = @intFromFloat(node.box.content_box.origin.x),
            .y = @intFromFloat(node.box.content_box.origin.y),
            .width = @intFromFloat(node.box.content_box.size.width),
            .height = @intFromFloat(node.box.content_box.size.height),
            .color = .{ .r = 200, .g = 100, .b = 0 },
        } });
    }

    for (node.children.items) |child| {
        try paintNode(layout_tree, child, commands);
    }
}
