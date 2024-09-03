const std = @import("std");

const log = std.log.scoped(.@"axiom/fetch");

pub const Fetcher = struct {
    name: []const u8,
    func: fn (allocator: std.mem.Allocator, uri: std.Uri) anyerror![]const u8,
};

const fetchers: []const Fetcher = &.{
    .{ .name = "http", .func = @import("fetch/http.zig").fetch },
};

pub fn fetch(allocator: std.mem.Allocator, url: []const u8) anyerror![]const u8 {
    const uri = std.Uri.parse(url) catch return error.InvalidUrl;

    inline for (fetchers) |fetcher| {
        if (std.mem.eql(u8, fetcher.name, uri.scheme)) {
            log.debug("{s} resolved to {s}", .{ url, fetcher.name });
            return try fetcher.func(allocator, uri);
        }
    }

    log.err("{s} didn't resolve", .{url});
    return error.InvalidScheme;
}
