//! CSS parser and data structures

const std = @import("std");

pub const Parser = @import("css/Parser.zig");
pub const Tokenizer = @import("css/Tokenizer.zig");
pub const Stylesheet = @import("css/Stylesheet.zig");
pub const Specificity = @import("css/Specificity.zig");

test "basic rule" {
    var parser = try Parser.fromSource(
        std.testing.allocator,
        \\foo {
        \\    color: #ff0000;
        \\}
        ,
    );
    defer parser.deinit();

    const stylesheet = try parser.parseStylesheet(null);

    try std.testing.expectEqualDeep(Stylesheet{
        .location = null,
        .rules = &.{
            Stylesheet.Rule{
                .selectors = &.{
                    Stylesheet.Rule.Selector{
                        .simple = .{
                            .element_name = "foo",
                            .id = null,
                            .class = &.{},
                        },
                    },
                },
                .declarations = &.{
                    Stylesheet.Rule.Declaration{
                        .property = "color",
                        .value = .{ .color = .{
                            .r = 255,
                            .g = 0,
                            .b = 0,
                            .a = 255,
                        } },
                    },
                },
            },
        },
    }, stylesheet);

    try std.testing.expectEqualDeep(Specificity{
        .a = 0,
        .b = 0,
        .c = 1,
    }, stylesheet.rules[0].specificity());
}

fn expectRender(in: []const u8, out: []const u8) !void {
    var parser = try Parser.fromSource(std.testing.allocator, in);
    defer parser.deinit();

    const stylesheet = try parser.parseStylesheet(null);

    var out_list = std.ArrayList(u8).init(std.testing.allocator);
    defer out_list.deinit();

    try stylesheet.render(out_list.writer());

    try std.testing.expectEqualStrings(out, out_list.items);
}

fn expectRenderSame(src: []const u8) !void {
    try expectRender(src, src);
}

test "basic rendering" {
    try expectRenderSame(
        \\foo {
        \\    color: #ff0000;
        \\}
    );

    try expectRender(
        \\
        \\
        \\foo{color: #ff0000;     }
        \\
    ,
        \\foo {
        \\    color: #ff0000;
        \\}
    );
}

test {
    _ = std.testing.refAllDeclsRecursive(@This());
}
