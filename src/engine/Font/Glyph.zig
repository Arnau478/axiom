const Glyph = @This();

const std = @import("std");
const Buffer = @import("Buffer.zig");

contours: []const Contour,
bounding_box: BoundingBox,

pub const Point = struct {
    x: f32,
    y: f32,
};

pub const Contour = struct {
    points: []const Point,
};

pub const BoundingBox = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub fn deinit(glyph: Glyph, allocator: std.mem.Allocator) void {
    for (glyph.contours) |contour| {
        allocator.free(contour.points);
    }

    allocator.free(glyph.contours);
}

pub fn rasterize(glyph: Glyph, buffer: Buffer, size: usize) void {
    std.debug.assert(buffer.width >= @as(usize, @intFromFloat(glyph.bounding_box.width * @as(f32, @floatFromInt(size)))));
    std.debug.assert(buffer.height >= @as(usize, @intFromFloat(glyph.bounding_box.height * @as(f32, @floatFromInt(size)))));

    for (0..buffer.height) |buffer_y| {
        for (0..buffer.width) |buffer_x| {
            const x = (@as(f32, @floatFromInt(buffer_x)) + 0.5) / @as(f32, @floatFromInt(size)) + glyph.bounding_box.x;
            const y = (@as(f32, @floatFromInt(buffer.height - buffer_y - 1)) + 0.5) / @as(f32, @floatFromInt(size)) + glyph.bounding_box.y;

            var inside = false;

            for (glyph.contours) |contour| {
                for (0..contour.points.len) |point_idx| {
                    const p1 = contour.points[point_idx];
                    const p2 = contour.points[(point_idx + 1) % contour.points.len];

                    if (horizontalRayIntersectsSegment(x, y, p1, p2)) {
                        inside = !inside;
                    }
                }
            }

            buffer.at(buffer_x, buffer_y).* = if (inside) 255 else 0;
        }
    }
}

fn horizontalRayIntersectsSegment(x: f32, y: f32, p1: Point, p2: Point) bool {
    if (p1.y > p2.y) return horizontalRayIntersectsSegment(x, y, p2, p1);

    if (p1.y <= y and y < p2.y) {
        const x_intersection = (p2.x - p1.x) * (y - p1.y) / (p2.y - p1.y + 1e-6) + p1.x;
        return x < x_intersection;
    } else return false;
}
