const std = @import("std");
const ui = @import("ui.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub const std_options = struct {
    pub const fmt_max_depth = 16;
};

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.debug.print("Usage: {s} <url>\n", .{args[0]});
    } else {
        try ui.app(allocator, args[1]);
    }
}
