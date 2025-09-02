const std = @import("std");
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

pub fn generateBox(allocator: std.mem.Allocator, style_tree: style.StyleTree, style_node_id: style.StyleTree.NodeId) !*Box {
    const style_node = style_tree.getNode(style_node_id).?.*;
    const computed_style = style_tree.getComputedStyle(style_node.computed_style).?.*;

    if (computed_style.display.generatesNoBox()) {
        @panic("TODO");
    } else {
        const principal_box: *Box = try .init(allocator, computed_style, style_node.element);
        errdefer principal_box.deinit(allocator);

        if (style_node.children.len > 0) {
            switch (computed_style.display.containerType()) {
                .block => {
                    var current_anonymous_box: ?*Box = null;

                    for (style_node.children) |child_id| {
                        const child = style_tree.getNode(child_id).?.*;
                        const child_computed_style = style_tree.getComputedStyle(child.computed_style).?.*;

                        if (child_computed_style.display.generatesNoBox()) continue;

                        switch (child_computed_style.display.boxLevel()) {
                            .block => {
                                current_anonymous_box = null;

                                const child_box = try generateBox(allocator, style_tree, child_id);
                                try principal_box.appendChild(allocator, child_box);
                            },
                            .@"inline" => {
                                if (current_anonymous_box == null) {
                                    current_anonymous_box = try Box.init(allocator, computed_style.inheritedOrInitial(), null);
                                    errdefer current_anonymous_box.?.deinit(allocator);
                                    try principal_box.appendChild(allocator, current_anonymous_box.?);
                                }

                                std.debug.assert(principal_box.children.getLast() == current_anonymous_box.?);

                                const child_box = try generateBox(allocator, style_tree, child_id);
                                try current_anonymous_box.?.appendChild(allocator, child_box);
                            },
                        }
                    }
                },
                .@"inline" => @panic("TODO"),
            }
        }

        return principal_box;
    }
}

pub fn reflow(root: *Box, viewport_size: Size) void {
    reflowBox(root, .{ .origin = .zero, .size = viewport_size }, viewport_size);
}

pub fn reflowBox(box: *Box, containing_block: Rect, viewport_size: Size) void {
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
