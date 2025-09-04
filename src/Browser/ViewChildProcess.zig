const ViewChildProcess = @This();

const std = @import("std");
const serialize = @import("../serialize.zig");
const ipc = @import("../ipc.zig");

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

pub fn send(process: ViewChildProcess, request: ipc.Request) error{RequestError}!void {
    var stdin_buffer: [1024]u8 = undefined;
    var stdin_writer = process.child.stdin.?.writer(&stdin_buffer);
    const stdin = &stdin_writer.interface;

    stdin.writeByte(0x16) catch return error.RequestError; // SYN

    serialize.write(ipc.Request, request, stdin) catch return error.RequestError;

    stdin.flush() catch return error.RequestError;
}

pub fn recv(process: ViewChildProcess, allocator: std.mem.Allocator, comptime response_type: std.meta.Tag(ipc.Response)) error{InvalidResponse}!@FieldType(ipc.Response, @tagName(response_type)) {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_reader = process.child.stdout.?.reader(&stdout_buffer);
    const stdout = &stdout_reader.interface;

    const ack_byte = stdout.takeByte() catch return error.InvalidResponse;
    if (ack_byte != 0x06) return error.InvalidResponse;
    const response = serialize.read(ipc.Response, allocator, stdout) catch return error.InvalidResponse;

    if (std.meta.activeTag(response) != response_type) return error.InvalidResponse;
    return @field(response, @tagName(response_type));
}
