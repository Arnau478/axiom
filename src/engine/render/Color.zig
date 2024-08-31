const Color = @This();

const std = @import("std");

r: u8,
g: u8,
b: u8,

pub fn toFloats(color: Color) [3]f32 {
    return [3]f32{
        @as(f32, @floatFromInt(color.r)) / 255.0,
        @as(f32, @floatFromInt(color.g)) / 255.0,
        @as(f32, @floatFromInt(color.b)) / 255.0,
    };
}

pub fn comptimeHex(comptime hex: []const u8) Color {
    std.debug.assert(hex[0] == '#');

    var buf: [4]u8 = undefined;
    const bytes = std.fmt.hexToBytes(&buf, hex[1..]) catch unreachable;

    switch (bytes.len) {
        3 => return .{
            .r = bytes[0],
            .g = bytes[1],
            .b = bytes[2],
        },
        else => unreachable,
    }
}
