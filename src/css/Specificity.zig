const std = @import("std");

const Specificity = @This();

a: usize,
b: usize,
c: usize,

pub fn order(lhs: Specificity, rhs: Specificity) std.math.Order {
    if (lhs.a < rhs.a) return .lt;
    if (lhs.a > rhs.a) return .gt;
    if (lhs.b < rhs.b) return .lt;
    if (lhs.b > rhs.b) return .gt;
    if (lhs.c < rhs.c) return .lt;
    if (lhs.c > rhs.c) return .gt;

    return .eq;
}

pub fn add(lhs: Specificity, rhs: Specificity) Specificity {
    return .{
        .a = lhs.a + rhs.a,
        .b = lhs.b + rhs.b,
        .c = lhs.c + rhs.c,
    };
}
