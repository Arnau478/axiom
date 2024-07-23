const std = @import("std");
const html = @import("html");
const css = @import("css");

pub const EdgeSizes = @import("layout/EdgeSizes.zig");
pub const Style = @import("layout/Style.zig");
pub const Tree = @import("layout/Tree.zig");

pub fn layout(allocator: std.mem.Allocator, dom: html.Dom, stylesheet: css.Stylesheet) !Tree {
    var tree: Tree = .{
        .allocator = allocator,
        .root = null,
    };

    if (dom.document.root) |dom_root| {
        const root = try allocator.create(Tree.Node);
        errdefer allocator.destroy(root);

        root.* = try layoutElement(allocator, dom_root.*, stylesheet);
        tree.root = root;
    }

    return tree;
}

fn layoutElement(allocator: std.mem.Allocator, element: html.Dom.Element, stylesheet: css.Stylesheet) !Tree.Node {
    const style = Style.get(element, stylesheet);

    // TODO: Skip if display is none

    var children: std.ArrayListUnmanaged(Tree.Node) = .{};
    errdefer children.deinit(allocator);

    for (element.children.items) |child| {
        switch (child) {
            .element => |child_element| try children.append(
                allocator,
                try layoutElement(allocator, child_element.*, stylesheet),
            ),
            .text => {},
        }
    }

    return .{
        .style = style,
        .children = children,
    };
}

test {
    var dom = html.Dom.init(std.testing.allocator);
    defer dom.deinit();

    var html_parser = try html.Parser.init(
        std.testing.allocator,
        \\<!DOCTYPE html>
        \\<html>
        \\    <head>
        \\    </head>
        \\    <body>
        \\    </body>
        \\</html>
    ,
        &dom,
    );
    defer html_parser.deinit();

    try html_parser.parse();

    var css_parser = try css.Parser.fromSource(
        std.testing.allocator,
        \\* {
        \\    color: #ff0000;
        \\    background-color: #0000ff;
        \\}
        ,
    );
    defer css_parser.deinit();

    const stylesheet = try css_parser.parseStylesheet(null);

    const tree = try layout(std.testing.allocator, dom, stylesheet);
    defer tree.deinit();

    const expected_style: Style = .{
        .color = .{ .r = 255, .g = 0, .b = 0 },
        .background_color = .{ .r = 0, .g = 0, .b = 255 },
        .padding = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
    };

    try std.testing.expectEqualDeep(2, tree.root.?.*.children.items.len);
    try std.testing.expectEqualDeep(0, tree.root.?.*.children.items[0].children.items.len);
    try std.testing.expectEqualDeep(0, tree.root.?.*.children.items[1].children.items.len);
    try std.testing.expectEqualDeep(expected_style, tree.root.?.*.style);
    try std.testing.expectEqualDeep(expected_style, tree.root.?.*.children.items[0].style);
    try std.testing.expectEqualDeep(expected_style, tree.root.?.*.children.items[1].style);
}
