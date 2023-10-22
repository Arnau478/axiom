const EdgeSizes = @This();

left: f64,
right: f64,
top: f64,
bottom: f64,

pub inline fn zero() EdgeSizes {
    return .{
        .left = 0,
        .right = 0,
        .top = 0,
        .bottom = 0,
    };
}
