const std = @import("std");

const Dom = @This();

document: Document,
allocator: std.mem.Allocator,

pub const ElementOrText = union(enum) {
    element: *Element,
    text: *Text,

    pub fn deinit(self: ElementOrText, allocator: std.mem.Allocator) void {
        switch (self) {
            inline else => |node| {
                node.deinit(allocator);
                allocator.destroy(node);
            },
        }
    }

    pub fn printTree(self: ElementOrText, depth: usize, writer: anytype) anyerror!void {
        switch (self) {
            inline else => |node| try node.printTree(depth, writer),
        }
    }
};

pub const Element = struct {
    tag_name: []const u8,
    children: std.ArrayListUnmanaged(ElementOrText),

    pub fn deinit(self: *Element, allocator: std.mem.Allocator) void {
        allocator.free(self.tag_name);

        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
    }

    pub fn printTree(self: Element, depth: usize, writer: anytype) !void {
        for (0..depth) |_| _ = try writer.write("  ");

        try writer.print("{s}\n", .{self.tag_name});

        for (self.children.items) |child| {
            try child.printTree(depth + 1, writer);
        }
    }
};

pub const Attribute = struct {};

pub const Text = struct {
    data: std.ArrayListUnmanaged(u8),

    pub fn deinit(self: *Text, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
    }

    pub fn printTree(self: Text, depth: usize, writer: anytype) !void {
        _ = self;

        for (0..depth) |_| _ = try writer.write("  ");

        try writer.print("#text\n", .{});
    }
};

pub const Comment = struct {};

pub const Document = struct {
    doctype: ?Doctype,
    root: ?*Element,
    mode: Mode = .no_quirks,

    pub const Mode = enum {
        no_quirks,
        quirks,
        limited_quirks,
    };

    pub fn deinit(self: Document, allocator: std.mem.Allocator) void {
        if (self.doctype) |doctype| {
            doctype.deinit(allocator);
        }

        if (self.root) |root| {
            root.deinit(allocator);
            allocator.destroy(root);
        }
    }

    pub fn printTree(self: Document, writer: anytype) !void {
        switch (self.mode) {
            .no_quirks => {},
            .quirks => try writer.print("<quirks>\n", .{}),
            .limited_quirks => try writer.print("<limited-quirks>\n", .{}),
        }

        if (self.root) |root| {
            try root.printTree(0, writer);
        } else {
            try writer.print("[empty]\n", .{});
        }
    }
};
pub const Doctype = struct {
    name: []const u8,
    public: []const u8,
    system: []const u8,

    pub fn deinit(self: Doctype, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.public);
        allocator.free(self.system);
    }
};

pub fn init(allocator: std.mem.Allocator) Dom {
    return .{
        .allocator = allocator,
        .document = .{
            .doctype = null,
            .root = null,
        },
    };
}

pub fn deinit(self: Dom) void {
    self.document.deinit(self.allocator);
}

pub fn printTree(self: Dom, writer: anytype) !void {
    try self.document.printTree(writer);
}
