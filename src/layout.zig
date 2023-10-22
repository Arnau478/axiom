const std = @import("std");
const dom = @import("dom.zig");
const Stylesheet = @import("Stylesheet.zig");
const Rect = @import("Rect.zig");
const EdgeSizes = @import("EdgeSizes.zig");

pub const Dimensions = struct {
    content: Rect,
    padding: EdgeSizes,
    border: EdgeSizes,
    margin: EdgeSizes,

    pub inline fn zero() Dimensions {
        return .{
            .content = Rect.zero(),
            .padding = EdgeSizes.zero(),
            .border = EdgeSizes.zero(),
            .margin = EdgeSizes.zero(),
        };
    }

    pub inline fn paddingRect(self: Dimensions) Rect {
        return self.content.expanded(self.padding);
    }

    pub inline fn borderRect(self: Dimensions) Rect {
        return self.paddingRect().expanded(self.border);
    }

    pub inline fn marginRect(self: Dimensions) Rect {
        return self.borderRect().expanded(self.margin);
    }
};

pub const Box = struct {
    dimensions: Dimensions,
    box_type: union(Type) {
        block_node: dom.Node,
        inline_node: dom.Node,
        block_anon,
    },
    children: []Box,

    const Type = enum {
        block_node,
        inline_node,
        block_anon,
    };

    pub fn layout(self: *Box, containing_block: Dimensions) void {
        switch (self.box_type) {
            .block_node => self.layoutBlock(containing_block),
            else => @panic("Unimplemented"),
        }
    }

    fn layoutBlock(self: *Box, containing_block: Dimensions) void {
        self.calculateBlockWidth(containing_block);
        self.calculateBlockPosition(containing_block);
        self.layoutBlockChildren();
        self.calculateBlockHeight();
    }

    fn calculateBlockWidth(self: *Box, containing_block: Dimensions) void {
        const node = self.box_type.block_node;

        const zero = Stylesheet.Value{ .length = .{ .magnitude = 0, .unit = .px } };

        var width = node.getProperty("width") orelse Stylesheet.Value{ .keyword = Stylesheet.Value.Keyword.fromStr("auto") };

        var margin_left = node.getProperty("margin-left") orelse node.getProperty("margin") orelse zero;
        var margin_right = node.getProperty("margin-right") orelse node.getProperty("margin") orelse zero;

        const border_left = node.getProperty("border-left-width") orelse node.getProperty("border-width") orelse zero;
        const border_right = node.getProperty("border-right-width") orelse node.getProperty("border-width") orelse zero;

        const padding_left = node.getProperty("padding-left") orelse node.getProperty("padding") orelse zero;
        const padding_right = node.getProperty("padding-right") orelse node.getProperty("padding") orelse zero;

        var sum: f64 = 0;
        inline for (&.{ margin_left, margin_right, border_left, border_right, padding_left, padding_right, width }) |v| {
            sum += v.asPx() orelse 0;
        }

        if (!width.isKeyword("auto") and sum > containing_block.content.w) {
            if (margin_left.isKeyword("auto")) margin_left = Stylesheet.Value{ .length = .{ .magnitude = 0, .unit = .px } };
            if (margin_right.isKeyword("auto")) margin_right = Stylesheet.Value{ .length = .{ .magnitude = 0, .unit = .px } };
        }

        const underflow = containing_block.content.w - sum;

        if (width.isKeyword("auto")) {
            if (margin_left.isKeyword("auto")) margin_left = Stylesheet.Value{ .length = .{ .magnitude = 0, .unit = .px } };
            if (margin_right.isKeyword("auto")) margin_right = Stylesheet.Value{ .length = .{ .magnitude = 0, .unit = .px } };

            if (underflow >= 0) {
                width = Stylesheet.Value{ .length = .{ .magnitude = underflow, .unit = .px } };
            } else {
                width = Stylesheet.Value{ .length = .{ .magnitude = 0, .unit = .px } };
                margin_right = Stylesheet.Value{ .length = .{ .magnitude = (margin_right.asPx() orelse 0) + underflow, .unit = .px } };
            }
        } else {
            if (!margin_left.isKeyword("auto") and !margin_right.isKeyword("auto")) {
                margin_right = Stylesheet.Value{ .length = .{ .magnitude = (margin_right.asPx() orelse 0) + underflow, .unit = .px } };
            } else if (margin_left.isKeyword("auto") and !margin_right.isKeyword("auto")) {
                margin_left = Stylesheet.Value{ .length = .{ .magnitude = underflow, .unit = .px } };
            } else if (!margin_left.isKeyword("auto") and margin_right.isKeyword("auto")) {
                margin_right = Stylesheet.Value{ .length = .{ .magnitude = underflow, .unit = .px } };
            } else if (margin_left.isKeyword("auto") and margin_right.isKeyword("auto")) {
                margin_left = Stylesheet.Value{ .length = .{ .magnitude = underflow / 2, .unit = .px } };
                margin_right = Stylesheet.Value{ .length = .{ .magnitude = underflow / 2, .unit = .px } };
            }
        }

        self.dimensions.content.w = width.asPx() orelse 0;

        self.dimensions.padding.left = padding_left.asPx() orelse 0;
        self.dimensions.padding.right = padding_right.asPx() orelse 0;

        self.dimensions.border.left = border_left.asPx() orelse 0;
        self.dimensions.border.right = border_right.asPx() orelse 0;

        self.dimensions.margin.left = margin_left.asPx() orelse 0;
        self.dimensions.margin.right = margin_right.asPx() orelse 0;
    }

    fn calculateBlockPosition(self: *Box, containing_block: Dimensions) void {
        const node = self.box_type.block_node;
        const d = &self.dimensions;

        const zero = Stylesheet.Value{ .length = .{ .magnitude = 0, .unit = .px } };

        d.margin.top = (node.getProperty("margin-top") orelse (node.getProperty("margin") orelse zero)).asPx() orelse 0;
        d.margin.bottom = (node.getProperty("margin-bottom") orelse (node.getProperty("margin") orelse zero)).asPx() orelse 0;

        d.border.top = (node.getProperty("border-top-width") orelse (node.getProperty("border-width") orelse zero)).asPx() orelse 0;
        d.border.bottom = (node.getProperty("border-bottom-width") orelse (node.getProperty("border-width") orelse zero)).asPx() orelse 0;

        d.padding.top = (node.getProperty("padding-top") orelse (node.getProperty("padding") orelse zero)).asPx() orelse 0;
        d.padding.bottom = (node.getProperty("padding-bottom") orelse (node.getProperty("padding") orelse zero)).asPx() orelse 0;

        d.content.x = containing_block.content.x + d.margin.left + d.border.left + d.padding.left;
        d.content.y = containing_block.content.h + containing_block.content.y + d.margin.top + d.border.top + d.padding.top;
    }

    fn layoutBlockChildren(self: *Box) void {
        var d = &self.dimensions;
        for (self.children, 0..) |_, i| {
            self.children[i].layout(d.*);

            d.content.h += self.children[i].dimensions.marginRect().h;
        }
    }

    fn calculateBlockHeight(self: *Box) void {
        const node = self.box_type.block_node;
        if (node.getProperty("height")) |height| {
            switch (height) {
                .length => |length| switch (length.unit) {
                    .px => self.dimensions.content.h = length.magnitude,
                },
                else => {},
            }
        }
    }

    pub fn print(self: Box) void {
        self.printIndent(0);
    }

    pub fn printIndent(self: Box, depth: usize) void {
        for (0..depth) |_| std.debug.print("  ", .{});
        std.debug.print("[{s}] content=(x={d}, y={d}, w={d}, h={d})\n", .{
            @tagName(self.box_type),
            self.dimensions.content.x,
            self.dimensions.content.y,
            self.dimensions.content.w,
            self.dimensions.content.h,
        });

        for (self.children) |child| {
            child.printIndent(depth + 1);
        }
    }
};

pub fn makeTree(dom_node: dom.Node, allocator: std.mem.Allocator) !Box {
    var root: Box = switch (dom_node.getDisplay()) {
        .block => .{
            .box_type = .{ .block_node = dom_node },
            .dimensions = Dimensions.zero(),
            .children = &.{},
        },
        .@"inline" => .{
            .box_type = .{ .inline_node = dom_node },
            .dimensions = Dimensions.zero(),
            .children = &.{},
        },
        .none => return error.RootDisplayNone,
    };

    var children = std.ArrayList(Box).init(allocator);

    var last_anon: ?Box = null;
    for (dom_node.children) |child| {
        switch (child.getDisplay()) {
            .block => {
                last_anon = null;
                try children.append(try makeTree(child, allocator));
            },
            .@"inline" => {
                var slice = allocator.alloc(Box, 1) catch @panic("OOM");
                slice[0] = try makeTree(child, allocator);
                children.append(
                    if (last_anon) |anon| anon else blk: {
                        const anon = .{
                            .dimensions = Dimensions.zero(),
                            .box_type = .block_anon,
                            .children = slice,
                        };
                        last_anon = anon;
                        break :blk anon;
                    },
                ) catch @panic("OOM");
            },
            .none => {},
        }
    }

    root.children = children.items;

    return root;
}

pub fn layoutTree(dom_node: dom.Node, allocator: std.mem.Allocator, original_viewport: Rect) !Box {
    var viewport = original_viewport;
    viewport.h = 0;

    var root = try makeTree(dom_node, allocator);

    root.layout(.{
        .content = viewport,
        .padding = EdgeSizes.zero(),
        .border = EdgeSizes.zero(),
        .margin = EdgeSizes.zero(),
    });

    return root;
}
