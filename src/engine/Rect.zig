const Rect = @This();

const engine = @import("engine.zig");

x: f64,
y: f64,
w: f64,
h: f64,

pub fn size(rect: Rect) engine.Size {
    return .{
        .w = rect.w,
        .h = rect.h,
    };
}

pub const Corner = enum {
    top_left,
    top_right,
    bottom_right,
    bottom_left,
};

pub fn cornerPos(rect: Rect, corner: Corner) @Vector(2, f64) {
    return switch (corner) {
        .top_left => .{ rect.x, rect.y },
        .top_right => .{ rect.x + rect.w, rect.y },
        .bottom_right => .{ rect.x + rect.w, rect.y + rect.h },
        .bottom_left => .{ rect.x, rect.y + rect.h },
    };
}
