const std = @import("std");
const Browser = @import("Browser.zig");
const ViewProcess = @import("ViewProcess.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // TODO: Proper argument parsing
    if (args.len == 1) {
        var browser = try Browser.init(allocator);
        defer browser.deinit();

        try browser.run();
    } else if (args.len == 2 and std.mem.eql(u8, args[1], "--view-process")) {
        var view_process = try ViewProcess.init(allocator);
        defer view_process.deinit();

        try view_process.run();
    }
}
