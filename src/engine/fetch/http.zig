const std = @import("std");

const user_agent = "Axiom"; // TODO: Proper UA string

const log = std.log.scoped(.@"axiom/fetch/http");

pub fn fetch(allocator: std.mem.Allocator, uri: std.Uri) ![]const u8 {
    log.debug("Fetching {}", .{uri});

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var server_header_buffer: [4096]u8 = undefined;

    var req = try client.open(.GET, uri, .{
        .version = .@"HTTP/1.1",
        .handle_continue = true,
        .keep_alive = false, // TODO: Keep the client
        .redirect_behavior = .unhandled,
        .server_header_buffer = &server_header_buffer,
        .headers = .{
            .user_agent = .{
                .override = user_agent,
            },
        },
    });
    defer req.deinit();

    try req.send();
    try req.finish();

    try req.wait();

    log.debug("Status: {d} {s}", .{ @intFromEnum(req.response.status), @tagName(req.response.status) });

    // TODO: Return a reader?
    return try req.reader().readAllAlloc(allocator, std.math.maxInt(usize));
}
