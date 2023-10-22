const std = @import("std");

pub fn fetch(uri: std.Uri, allocator: std.mem.Allocator) ![]const u8 {
    const file = try std.fs.cwd().openFile(uri.path, .{ .mode = .read_only });
    defer file.close();

    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}
