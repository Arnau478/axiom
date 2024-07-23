//! HTML parser and data structures

const std = @import("std");

pub const Tokenizer = @import("html/Tokenizer.zig");
pub const Parser = @import("html/Parser.zig");
pub const Dom = @import("html/Dom.zig");

fn testParse(source: []const u8, dom_tree: []const u8) !void {
    var dom = Dom.init(std.testing.allocator);
    defer dom.deinit();

    var parser = try Parser.init(
        std.testing.allocator,
        source,
        &dom,
    );
    defer parser.deinit();

    try parser.parse();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try dom.printTree(out.writer());

    try std.testing.expectEqualStrings(dom_tree, out.items[0 .. out.items.len - 1]);
}

test {
    try testParse(
        \\<!DOCTYPE html><html><head></head><body></body></html>
    ,
        \\html
        \\  head
        \\  body
    );

    try testParse(
        \\<!DOCTYPE html>
        \\<html>
        \\    <head>
        \\    </head>
        \\    <body>
        \\    </body>
        \\</html>
    ,
        \\html
        \\  head
        \\    #text
        \\  #text
        \\  body
        \\    #text
    );
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
