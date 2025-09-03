const std = @import("std");
const build_options = @import("build_options");
const layout = @import("layout.zig");
const render = @import("render.zig");

pub fn paint(allocator: std.mem.Allocator, box: *const layout.Box) ![]const render.Command {
    var commands = std.ArrayList(render.Command).init(allocator);
    defer commands.deinit();

    try paintBox(box, &commands);

    return try commands.toOwnedSlice();
}

fn paintBox(box: *const layout.Box, commands: *std.ArrayList(render.Command)) !void {
    if (box.computed_style.background_color.a != 0) {
        std.debug.assert(box.computed_style.background_color.a == 255); // TODO: Transparency

        try commands.append(.{ .simple_rect = .{
            .x = @intFromFloat(box.box_model.borderBox().origin.x),
            .y = @intFromFloat(box.box_model.borderBox().origin.y),
            .width = @intFromFloat(box.box_model.borderBox().size.width),
            .height = @intFromFloat(box.box_model.borderBox().size.height),
            .color = .{
                .r = box.computed_style.background_color.r,
                .g = box.computed_style.background_color.g,
                .b = box.computed_style.background_color.b,
            },
        } });
    }

    // TODO: Borders

    // TODO: Text

    if (build_options.paint_box_model) {
        try commands.append(.{ .simple_rect = .{
            .x = @intFromFloat(box.box_model.marginBox().origin.x),
            .y = @intFromFloat(box.box_model.marginBox().origin.y),
            .width = @intFromFloat(box.box_model.marginBox().size.width),
            .height = @intFromFloat(box.box_model.marginBox().size.height),
            .color = .{ .r = 100, .g = 0, .b = 200 },
        } });
        try commands.append(.{ .simple_rect = .{
            .x = @intFromFloat(box.box_model.borderBox().origin.x),
            .y = @intFromFloat(box.box_model.borderBox().origin.y),
            .width = @intFromFloat(box.box_model.borderBox().size.width),
            .height = @intFromFloat(box.box_model.borderBox().size.height),
            .color = .{ .r = 100, .g = 100, .b = 100 },
        } });
        try commands.append(.{ .simple_rect = .{
            .x = @intFromFloat(box.box_model.paddingBox().origin.x),
            .y = @intFromFloat(box.box_model.paddingBox().origin.y),
            .width = @intFromFloat(box.box_model.paddingBox().size.width),
            .height = @intFromFloat(box.box_model.paddingBox().size.height),
            .color = .{ .r = 0, .g = 200, .b = 100 },
        } });
        try commands.append(.{ .simple_rect = .{
            .x = @intFromFloat(box.box_model.content_box.origin.x),
            .y = @intFromFloat(box.box_model.content_box.origin.y),
            .width = @intFromFloat(box.box_model.content_box.size.width),
            .height = @intFromFloat(box.box_model.content_box.size.height),
            .color = .{ .r = 200, .g = 100, .b = 0 },
        } });
    }

    for (box.children.items) |child| {
        try paintBox(child, commands);
    }
}
