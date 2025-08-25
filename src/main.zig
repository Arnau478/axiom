const std = @import("std");
const engine = @import("engine");

const Request = union(enum(u8)) {
    navigate_to_url: []const u8,
};

const Response = union(enum(u8)) {};

const ViewChildProcess = struct {
    child: std.process.Child,

    pub fn init(allocator: std.mem.Allocator) !ViewChildProcess {
        var process: ViewChildProcess = .{
            .child = .init(&.{ "/proc/self/exe", "--view-process" }, allocator),
        };

        process.child.stdin_behavior = .Pipe;
        process.child.stdout_behavior = .Pipe;
        process.child.stderr_behavior = .Inherit;

        try process.child.spawn();

        std.log.debug("Created view process {d}", .{process.child.id});

        return process;
    }

    pub fn kill(process: *ViewChildProcess) void {
        std.log.debug("Killing view process {d}", .{process.child.id});

        _ = process.child.kill() catch {};
    }

    fn send(process: ViewChildProcess, request: Request) error{RequestError}!void {
        process.child.stdin.?.writer().writeByte(0x16) catch return error.RequestError; // SYN
        process.child.stdin.?.writer().writeByte(@intFromEnum(std.meta.activeTag(request))) catch return error.RequestError;

        switch (request) {
            .navigate_to_url => |url| {
                process.child.stdin.?.writer().writeInt(u32, @intCast(url.len), .little) catch return error.RequestError;
                process.child.stdin.?.writeAll(url) catch return error.RequestError;
            },
        }
    }

    fn recv(process: ViewChildProcess, comptime response_type: std.meta.Tag(Response)) error{InvalidResponse}!@FieldType(Response, @tagName(response_type)) {
        const ack_byte = process.child.stdout.?.reader().readByte() catch return error.InvalidResponse;
        if (ack_byte != 0x06) return error.InvalidResponse;
        const type_byte = process.child.stdout.?.reader().readByte() catch return error.InvalidResponse;
        if (type_byte != @intFromEnum(response_type)) return error.InvalidResponse;

        switch (response_type) {
            .navigate_to_url => {},
        }
    }
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // TODO: Proper argument parsing
    if (args.len == 1) {
        var view_process = try ViewChildProcess.init(allocator);
        defer view_process.kill();
        std.log.debug("Sending navigate request", .{});
        try view_process.send(.{ .navigate_to_url = "https://example.org" });
        std.log.debug("Navigate request done", .{});
        std.time.sleep(std.time.ns_per_s);
    } else if (args.len == 2 and std.mem.eql(u8, args[1], "--view-process")) {
        std.log.debug("View process started", .{});
        while (true) {
            const stdin = std.io.getStdIn().reader();
            const stdout = std.io.getStdOut().writer();
            _ = stdout;

            const syn_byte = try stdin.readByte();
            if (syn_byte != 0x16) std.process.fatal("Invalid request, expected SYN (0x16), got 0x{x:0>2}", .{syn_byte});
            const request_type = try stdin.readEnum(std.meta.Tag(Request), .little);

            switch (request_type) {
                .navigate_to_url => {
                    const url_len = try stdin.readInt(u32, .little);
                    const url = try allocator.alloc(u8, url_len);
                    defer allocator.free(url);
                    _ = try stdin.readAll(url);

                    std.log.debug("Natigating to {s}", .{url});
                },
            }
        }
    }
}
