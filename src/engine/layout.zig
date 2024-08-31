const std = @import("std");
const engine = @import("engine.zig");

pub const BoxModel = @import("layout/BoxModel.zig");

pub fn reflow(tree: *engine.FrameTree) void {
    reflowNode(&tree.root, .{});
}

const ReflowState = struct {
    container_available_width: ?f64 = null,
};

fn reflowNode(node: *engine.FrameTree.Node, state: ReflowState) void {
    switch (node.type) {
        .viewport => |viewport| {
            std.debug.assert(state.container_available_width == null);
            std.debug.assert(node.children.items.len == 1);

            const child = &node.children.items[0];

            child.type.box.box_model.position = .{ 0, 0 };

            reflowNode(child, .{
                .container_available_width = viewport.size.w,
            });
        },
        .box => |*box| {
            // Offset position
            switch (box.type) {
                .block => {
                    box.box_model.position.? += .{
                        box.box_model.combinedBorderMargin().left,
                        box.box_model.combinedBorderMargin().top,
                    };
                },
            }

            // Determine node width
            switch (box.type) {
                .block => {
                    const container_width = @max(state.container_available_width.?, 0);

                    var width = container_width - box.box_model.combinedBorderMargin().horizontal();

                    // TODO: "width" property

                    const max_width: ?f64 = null; // TODO: "max-width" property
                    const min_width: ?f64 = null; // TODO: "min-width" property

                    if (max_width) |max| width = @min(max, width);
                    if (min_width) |min| width = @max(min, width);

                    box.box_model.box_width = width;
                },
            }

            var insertion_point = box.box_model.position.? +
                @as(@Vector(2, f64), .{ box.box_model.padding.left, box.box_model.padding.top });
            const first_insertion_point = insertion_point;
            var last_margin: ?f64 = null;
            for (node.children.items) |*child| {
                // Set the child's position
                switch (box.type) {
                    .block => {
                        child.type.box.box_model.position = insertion_point;
                    },
                }

                // Reflow child
                switch (box.type) {
                    .block => {
                        reflowNode(child, .{
                            .container_available_width = box.box_model.box_width.? - box.box_model.padding.horizontal(),
                        });
                    },
                }

                // Add to the node height
                insertion_point[1] += child.type.box.box_model.borderRect().?.h;
                insertion_point[1] += if (last_margin) |last|
                    @max(last, child.type.box.box_model.margin.top)
                else
                    child.type.box.box_model.margin.top;
                last_margin = child.type.box.box_model.margin.bottom;
            }

            // Set node height
            if (last_margin) |last| insertion_point[1] += last;
            box.box_model.box_height = (insertion_point - first_insertion_point)[1] +
                box.box_model.padding.vertical();
        },
    }
}
