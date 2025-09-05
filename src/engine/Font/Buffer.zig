const Buffer = @This();

const std = @import("std");

width: usize,
height: usize,
data: []u8,

pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Buffer {
    const data = try allocator.alloc(u8, width * height);
    return .{
        .width = width,
        .height = height,
        .data = data,
    };
}

pub fn deinit(buffer: Buffer, allocator: std.mem.Allocator) void {
    allocator.free(buffer.data);
}

pub fn at(buffer: Buffer, x: usize, y: usize) *u8 {
    std.debug.assert(buffer.data.len == buffer.width * buffer.height);
    std.debug.assert(x < buffer.width);
    std.debug.assert(y < buffer.height);

    return &buffer.data[y * buffer.width + x];
}
