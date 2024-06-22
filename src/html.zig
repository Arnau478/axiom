//! HTML parser and data structures

const std = @import("std");

pub const Parser = @import("html/Parser.zig");
pub const Tokenizer = @import("html/Tokenizer.zig");

pub fn parse(source: []const u8) !void {
    var tokenizer = Tokenizer{ .source = source };
    while (tokenizer.scanToken()) |tok| {
        std.log.err("{}", .{tok});
    }
}

test {
    try parse("<b>hello</b>");
    return error.Foo;
}

test {
    _ = std.testing.refAllDeclsRecursive(@This());
}
