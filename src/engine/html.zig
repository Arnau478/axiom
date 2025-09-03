const std = @import("std");
const Dom = @import("Dom.zig");

pub const Token = @import("html/Token.zig");
pub const Tokenizer = @import("html/Tokenizer.zig");
pub const TreeConstructor = @import("html/TreeConstructor.zig");

pub fn parse(allocator: std.mem.Allocator, dom: *Dom, document_id: Dom.DocumentId, source: []const u8) !void {
    var tree_constructor: TreeConstructor = .init(allocator, dom, document_id);
    defer tree_constructor.deinit();
    var tokenizer: Tokenizer = .{ .source = source };

    while (tokenizer.next()) |token| {
        try tree_constructor.dispatch(&tokenizer, source, token);
    }

    try tree_constructor.dispatch(&tokenizer, source, null);
}

test {
    const source =
        \\<!DOCTYPE html>
        \\<html>
        \\  <head></head>
        \\  <body>
        \\    <foo>This is a paragraph.</foo>
        \\  </body>
        \\</html>
    ;

    var dom = Dom.init(std.testing.allocator);
    defer dom.deinit();

    const document = try dom.createDocument();

    try parse(std.testing.allocator, &dom, document, source);
}
