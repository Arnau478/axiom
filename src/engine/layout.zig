const std = @import("std");
const Dom = @import("Dom.zig");
const Font = @import("Font.zig");
const style = @import("style.zig");

pub const Point = @import("layout/Point.zig");
pub const Size = @import("layout/Size.zig");
pub const EdgeSizes = @import("layout/EdgeSizes.zig");
pub const Rect = @import("layout/Rect.zig");
pub const Box = @import("layout/Box.zig");
pub const BoxModel = @import("layout/BoxModel.zig");

pub const ContainerBoxType = enum {
    block,
    @"inline",
};

pub const BoxLevel = enum {
    block,
    @"inline",
};

pub const Display = enum {
    block,
    @"inline",
    inline_block,
    list_item,
    none,

    pub fn boxLevel(display: Display) BoxLevel {
        return switch (display) {
            .block, .list_item => .block,
            .@"inline", .inline_block => .@"inline",
            .none => unreachable,
        };
    }

    pub fn containerType(display: Display) ContainerBoxType {
        return switch (display) {
            .block, .inline_block, .list_item => .block,
            .@"inline" => .@"inline",
            .none => unreachable,
        };
    }

    pub fn generatesNoBox(display: Display) bool {
        return display == .none;
    }
};

pub const Position = enum {
    static,
    relative,
    absolute,
    fixed,
    pub fn positioningScheme(position: Position) PositioningScheme {
        return switch (position) {
            .static => .normal_flow,
            .relative => @panic("TODO"),
            .absolute => @panic("TODO"),
            .fixed => @panic("TODO"),
        };
    }
};

pub const PositioningScheme = enum {
    normal_flow,
};

pub fn generateBox(allocator: std.mem.Allocator, dom: Dom, style_tree: style.StyleTree, style_node_id: style.StyleTree.NodeId, font: Font) !*Box {
    const style_node = style_tree.getNode(style_node_id).?.*;
    const computed_style = style_tree.getComputedStyle(style_node.computed_style).?.*;

    if (computed_style.display.generatesNoBox()) {
        @panic("TODO");
    } else {
        const principal_box: *Box = try .init(allocator, computed_style, style_node.dom_node);
        errdefer principal_box.deinit(allocator);

        switch (style_node.dom_node) {
            .element => {
                if (style_node.children.len > 0) {
                    switch (computed_style.display.containerType()) {
                        .block => {
                            var has_block_child = false;
                            var children_with_box_count: usize = 0;

                            for (style_node.children) |child_id| {
                                const child = style_tree.getNode(child_id).?.*;
                                const child_computed_style = style_tree.getComputedStyle(child.computed_style).?.*;

                                if (child_computed_style.display.generatesNoBox()) continue;

                                if (child_computed_style.display.boxLevel() == .block) {
                                    has_block_child = true;
                                    children_with_box_count += 1;
                                    break;
                                }
                            }

                            if (!has_block_child or children_with_box_count <= 1) {
                                for (style_node.children) |child_id| {
                                    const child = style_tree.getNode(child_id).?.*;
                                    const child_computed_style = style_tree.getComputedStyle(child.computed_style).?.*;

                                    if (child_computed_style.display.generatesNoBox()) continue;

                                    const child_box = try generateBox(allocator, dom, style_tree, child_id, font);
                                    try principal_box.appendChild(allocator, child_box);
                                }
                            } else {
                                var current_anonymous_box: ?*Box = null;

                                for (style_node.children) |child_id| {
                                    const child = style_tree.getNode(child_id).?.*;
                                    const child_computed_style = style_tree.getComputedStyle(child.computed_style).?.*;

                                    if (child_computed_style.display.generatesNoBox()) continue;

                                    switch (child_computed_style.display.boxLevel()) {
                                        .block => {
                                            current_anonymous_box = null;

                                            const child_box = try generateBox(allocator, dom, style_tree, child_id, font);
                                            try principal_box.appendChild(allocator, child_box);
                                        },
                                        .@"inline" => {
                                            if (current_anonymous_box == null) {
                                                current_anonymous_box = try Box.init(allocator, computed_style.inheritedOrInitial(), null);
                                                errdefer current_anonymous_box.?.deinit(allocator);
                                                try principal_box.appendChild(allocator, current_anonymous_box.?);
                                            }

                                            std.debug.assert(principal_box.children.getLast() == current_anonymous_box.?);

                                            const child_box = try generateBox(allocator, dom, style_tree, child_id, font);
                                            try current_anonymous_box.?.appendChild(allocator, child_box);
                                        },
                                    }
                                }
                            }
                        },
                        .@"inline" => @panic("TODO"),
                    }
                }
            },
            .text => {
                const raw_text_data = dom.getText(style_node.dom_node.text).?.data;
                const text_data = std.mem.trim(u8, raw_text_data, &.{ ' ', '\n', '\t', '\r', 0x0c });

                var iter: std.unicode.Utf8Iterator = .{ .bytes = text_data, .i = 0 };

                std.log.debug("\"{s}\"", .{text_data});

                while (iter.nextCodepoint()) |cp| {
                    const font_size = 64; // TODO

                    const glyph = (try font.getGlyph(allocator, cp)).?;
                    defer glyph.deinit(allocator);

                    var buffer: ?Font.Buffer = null;
                    if (glyph.contours.len > 0) {
                        buffer = try Font.Buffer.init(
                            allocator,
                            @intFromFloat(glyph.bounding_box.width * @as(f32, @floatFromInt(font_size))),
                            @intFromFloat(glyph.bounding_box.height * @as(f32, @floatFromInt(font_size))),
                        );
                        errdefer buffer.?.deinit(allocator);

                        glyph.rasterize(buffer.?, font_size);
                    }

                    try principal_box.text.append(allocator, .{
                        .buffer = buffer,
                        .glyph_offset = .{
                            .x = glyph.bounding_box.x * @as(f32, @floatFromInt(font_size)),
                            .y = (glyph.bounding_box.y + glyph.bounding_box.height) * -@as(f32, @floatFromInt(font_size)),
                        },
                        .advance_width = glyph.advance_width * @as(f32, @floatFromInt(font_size)),
                    });
                }
            },
            .comment => @panic("TODO"),
        }

        return principal_box;
    }
}

pub fn reflow(root: *Box, viewport_size: Size) void {
    reflowBox(root, .{ .origin = .zero, .size = viewport_size }, viewport_size);
}

pub fn reflowBox(box: *Box, containing_block: Rect, viewport_size: Size) void {
    if (box.dom_node.? == .text) {
        const line_height = 64; // TODO

        var cursor_x: f32 = 0;
        var line_count: usize = 0;
        var remaining_space: f32 = 0;

        for (box.text.items) |*component| {
            if (remaining_space <= component.advance_width) {
                line_count += 1;
                cursor_x = 0;
                remaining_space = containing_block.size.width;
            }

            component.component_offset = .{
                .x = cursor_x,
                .y = @as(f32, @floatFromInt(line_count)) * line_height,
            };

            cursor_x += component.advance_width;
            remaining_space -= component.advance_width;
        }

        box.box_model = .{
            .content_box = .{
                .origin = containing_block.origin,
                .size = .{ .width = containing_block.size.width, .height = @as(f32, @floatFromInt(line_count)) * line_height },
            },
            .padding = .zero,
            .border = .zero,
            .margin = .zero,
        };
    } else {
        switch (box.positioningScheme()) {
            .normal_flow => {
                box.predetermineDimensions(containing_block);
                box.predeterminePosition(containing_block);

                switch (box.containerType()) {
                    .block => {
                        // TODO: Inline formatting context

                        var current_content_height: f32 = 0;

                        for (box.children.items) |child| {
                            reflowBox(child, box.box_model.content_box.expand(.{
                                .top = -current_content_height,
                                .right = 0,
                                .bottom = 0,
                                .left = 0,
                            }), viewport_size);

                            current_content_height += child.box_model.marginBox().size.height;
                        }

                        box.box_model.content_box.size.height = current_content_height;
                    },
                    .@"inline" => @panic("TODO"),
                }

                box.finalizeDimensions(containing_block);
            },
        }
    }
}
