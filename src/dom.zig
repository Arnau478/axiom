const std = @import("std");
const Stylesheet = @import("Stylesheet.zig");

pub const AttrMap = std.StringHashMap(?[]const u8);

pub const NodeType = enum {
    text,
    element,
    stylesheet,
};

pub const Node = struct {
    children: []Node,
    node_type: union(NodeType) {
        text: []const u8,
        element: ElementData,
        stylesheet: Stylesheet,
    },
    specified_properties: ?Stylesheet.PropertyMap = null,

    pub const ElementData = struct {
        tag_name: []const u8,
        attributes: AttrMap,

        pub fn getId(self: *const ElementData) ?[]const u8 {
            return self.attributes.get("id") orelse null;
        }

        pub fn getClasses(self: *const ElementData, allocator: std.mem.Allocator) std.StringHashMap(void) {
            var res = std.StringHashMap(void).init(allocator);
            if (self.attributes.get("class")) |classes_maybe| {
                if (classes_maybe) |classes| {
                    var iterator = std.mem.splitScalar(u8, classes, ' ');
                    while (iterator.next()) |class| {
                        res.put(class, {}) catch @panic("OOM");
                    }
                }
            }
            return res;
        }

        pub fn matchesSelector(self: *const ElementData, selector: Stylesheet.Selector, allocator: std.mem.Allocator) bool {
            switch (selector) {
                .simple => {
                    if (selector.simple.tag_name) |tag_name| {
                        if (!std.mem.eql(u8, tag_name, self.tag_name)) return false;
                    }

                    if (selector.simple.id) |id| {
                        if (self.getId()) |self_id| {
                            if (!std.mem.eql(u8, id, self_id)) return false;
                        }
                    }

                    for (selector.simple.class) |class| {
                        var iter = self.getClasses(allocator).iterator();
                        var done = false;
                        while (iter.next()) |self_class| {
                            done = true;
                            if (!std.mem.eql(u8, class, self_class.key_ptr.*)) return false;
                        }
                        if (!done) return false;
                    }

                    return true;
                },
            }
        }
    };

    pub fn getProperty(self: *const Node, name: []const u8) ?Stylesheet.Value {
        return (self.specified_properties orelse return null).get(name) orelse null;
    }

    pub fn getDisplay(self: *const Node) Stylesheet.Display {
        return switch (self.getProperty("display") orelse return .@"inline") {
            .keyword => |keyword| if (keyword.isKeyword("block")) .block else if (keyword.isKeyword("none")) .none else .@"inline",
            else => .@"inline",
        };
    }

    pub fn getMixedStylesheet(self: *const Node, allocator: std.mem.Allocator) Stylesheet {
        var stylesheet = switch (self.node_type) {
            .stylesheet => |stylesheet| stylesheet,
            else => Stylesheet.empty(),
        };
        for (self.children) |child| {
            stylesheet.append(child.getMixedStylesheet(allocator), allocator);
        }
        return stylesheet;
    }

    pub fn print(self: *const Node) void {
        self.printIndent(0);
    }

    pub fn printIndent(self: *const Node, depth: usize) void {
        switch (self.node_type) {
            .text => |text| {
                for (0..depth) |_| std.debug.print("  ", .{});
                std.debug.print("(text) \"{s}\"\n", .{text});
            },
            .element => |element| {
                for (0..depth) |_| std.debug.print("  ", .{});
                std.debug.print("(element) <{s}>", .{element.tag_name});
                var iter = element.attributes.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.*) |value| {
                        std.debug.print(" {s}=\"{s}\"", .{ entry.key_ptr.*, value });
                    } else std.debug.print(" {s}", .{entry.key_ptr.*});
                }
                std.debug.print("\n", .{});
            },
            .stylesheet => |stylesheet| stylesheet.printIndent(depth + 1),
        }

        if (self.specified_properties) |specified_properties| {
            var iter = specified_properties.iterator();
            while (iter.next()) |prop| {
                for (0..depth + 1) |_| std.debug.print("  ", .{});
                std.debug.print("> {s} = {}\n", .{ prop.key_ptr.*, prop.value_ptr.* });
            }
        }

        for (self.children) |child| {
            child.printIndent(depth + 1);
        }
    }
};
