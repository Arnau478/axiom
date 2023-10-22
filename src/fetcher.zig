const std = @import("std");

const file = @import("fetcher/file.zig");

pub fn fetch(uri_txt: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const uri = try std.Uri.parse(uri_txt);

    if (std.mem.eql(u8, uri.scheme, "file")) {
        return try file.fetch(uri, allocator);
    } else {
        return error.UnknownScheme;
    }
}
