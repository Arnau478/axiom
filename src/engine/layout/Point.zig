const Point = @This();

x: f32,
y: f32,

pub fn add(lhs: Point, rhs: Point) Point {
    return .{
        .x = lhs.x + rhs.x,
        .y = lhs.y + rhs.y,
    };
}
