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
        .value = &.{
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
    }, stylesheet.value[0].specificity());
}

test {
    _ = std.testing.refAllDeclsRecursive(@This());
}
