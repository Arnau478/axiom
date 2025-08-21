const Rect = @This();

const Point = @import("Point.zig");
const Size = @import("Size.zig");
const EdgeSizes = @import("EdgeSizes.zig");

origin: Point,
size: Size,

pub fn expand(rect: Rect, edge_sizes: EdgeSizes) Rect {
    return .{
        .origin = .{
            .x = rect.origin.x - edge_sizes.left,
            .y = rect.origin.y - edge_sizes.top,
        },
        .size = .{
            .width = rect.size.width + edge_sizes.horizontal(),
            .height = rect.size.height + edge_sizes.vertical(),
        },
    };
}
