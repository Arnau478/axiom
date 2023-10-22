const std = @import("std");
const dom = @import("dom.zig");
const style = @import("style.zig");
const layout = @import("layout.zig");
const raster = @import("raster.zig");
const fetcher = @import("fetcher.zig");
const Parser = @import("Parser.zig");
const Stylesheet = @import("Stylesheet.zig");
const Rect = @import("Rect.zig");

const wapi = @import("ui/wapi/xlib.zig");

pub const Event = union(enum) {
    expose: struct {
        width: usize,
        height: usize,
    },
    key_press: struct {
        key: Key,
    },
};

pub const Key = enum {
    escape,
    shift,
    space,
    backspace,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
};

pub fn app(allocator: std.mem.Allocator, url: []const u8) !void {
    try wapi.init();
    defer wapi.deinit();

    var parser = Parser.init(allocator, try fetcher.fetch(url, allocator));

    var tree = try parser.parseHtml();
    style.styleDom(
        &tree,
        allocator,
        blk: {
            var css_parser = Parser.init(allocator, @embedFile("ua.css"));
            break :blk try css_parser.parseCss();
        },
        blk: {
            const txt = "";
            var css_parser = Parser.init(allocator, txt);
            break :blk try css_parser.parseCss();
        },
    );

    tree.print();

    while (true) {
        switch (wapi.getEvent()) {
            .expose => |expose| {
                const viewport: Rect = .{ .x = 0, .y = 0, .w = @floatFromInt(expose.width), .h = @floatFromInt(expose.height) };
                const layout_tree = try layout.layoutTree(tree, allocator, viewport);

                wapi.drawRectangle(viewport, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, true);
                const display_list = try raster.buildList(layout_tree, allocator);

                for (display_list) |cmd| {
                    switch (cmd) {
                        .solid_rect => |solid_rect| {
                            std.debug.print("{}\n", .{cmd});
                            wapi.drawRectangle(solid_rect.rect, solid_rect.color, true);
                        },
                    }
                }
            },
            .key_press => |key_press| {
                std.debug.print("{} pressed\n", .{key_press.key});
            },
        }
    }
}

inline fn xlibColor(color: Stylesheet.Value.Color) c_ulong {
    return @as(c_ulong, color.b) + (@as(c_ulong, color.g) << 8) + (@as(c_ulong, color.r) << 16);
}
