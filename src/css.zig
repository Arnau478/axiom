//! CSS parser and data structures

const std = @import("std");

pub const Parser = @import("css/Parser.zig");
pub const Tokenizer = @import("css/Tokenizer.zig");

pub fn parse(source: []const u8) !void {
    var tokenizer = Tokenizer{ .source = source };
    while (tokenizer.next()) |tok| {
        std.log.err("{}", .{tok});
    }
}

test {
    try parse(
        \\foo {
        \\    color: red;
        \\}
    );
    return error.Foo;
}

test {
    _ = std.testing.refAllDeclsRecursive(@This());
}
