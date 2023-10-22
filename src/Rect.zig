const EdgeSizes = @import("EdgeSizes.zig");

const Rect = @This();

x: f64,
y: f64,
w: f64,
h: f64,

pub inline fn zero() Rect {
    return .{
        .x = 0,
        .y = 0,
        .w = 0,
        .h = 0,
    };
}

pub inline fn expanded(self: Rect, edges: EdgeSizes) Rect {
    return .{
        .x = self.x - edges.left,
        .y = self.y - edges.top,
        .w = self.w + edges.left + edges.right,
        .h = self.h + edges.top + edges.bottom,
    };
}
