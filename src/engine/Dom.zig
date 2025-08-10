const Dom = @This();

const std = @import("std");

allocator: std.mem.Allocator,
documents: std.ArrayListUnmanaged(Document),
elements: std.ArrayListUnmanaged(Element),
texts: std.ArrayListUnmanaged(Text),
comments: std.ArrayListUnmanaged(Comment),
attributes: std.ArrayListUnmanaged(Attribute),
document_types: std.ArrayListUnmanaged(DocumentType),
strings: std.StringHashMapUnmanaged([]const u8),

pub fn init(allocator: std.mem.Allocator) Dom {
    return .{
        .allocator = allocator,
        .documents = .{},
        .elements = .{},
        .texts = .{},
        .comments = .{},
        .attributes = .{},
        .document_types = .{},
        .strings = .{},
    };
}

pub fn deinit(dom: *Dom) void {
    for (dom.documents.items) |*document| {
        document.children.deinit(dom.allocator);
    }

    for (dom.elements.items) |*element| {
        element.children.deinit(dom.allocator);
        element.attributes.deinit(dom.allocator);
    }

    var string_iter = dom.strings.iterator();
    while (string_iter.next()) |entry| {
        dom.allocator.free(entry.value_ptr.*);
    }
    dom.strings.deinit(dom.allocator);

    dom.documents.deinit(dom.allocator);
    dom.elements.deinit(dom.allocator);
    dom.texts.deinit(dom.allocator);
    dom.comments.deinit(dom.allocator);
    dom.attributes.deinit(dom.allocator);
    dom.document_types.deinit(dom.allocator);
}

pub fn internString(dom: *Dom, str: []const u8) ![]const u8 {
    if (dom.strings.get(str)) |res| {
        return res;
    }

    const res = try dom.allocator.dupe(u8, str);
    try dom.strings.put(dom.allocator, res, res);
    return res;
}

const NodeIdType = u32;
pub const DocumentId = enum(NodeIdType) { _ };
pub const ElementId = enum(NodeIdType) { _ };
pub const TextId = enum(NodeIdType) { _ };
pub const CommentId = enum(NodeIdType) { _ };
pub const AttributeId = enum(NodeIdType) { _ };
pub const DocumentTypeId = enum(NodeIdType) { _ };

pub const ContentNode = union(enum) {
    element: ElementId,
    text: TextId,
    comment: CommentId,
};

pub const DocumentChild = union(enum) {
    element: ElementId,
    comment: CommentId,
    document_type: DocumentTypeId,
};

pub const Document = struct {
    children: std.ArrayListUnmanaged(DocumentChild) = .{},
    // Shortcuts
    element: ?ElementId = null,
    document_type: ?DocumentTypeId = null,
};

pub const Element = struct {
    tag_name: []const u8,
    namespace: ?[]const u8 = null,
    attributes: std.ArrayListUnmanaged(AttributeId) = .{},
    children: std.ArrayListUnmanaged(ContentNode) = .{},
    parent: ?ElementId = null,
};

pub const Text = struct {
    data: []const u8,
    parent: ?ElementId = null,
};

pub const Comment = struct {
    data: []const u8,
    parent: ?ElementId = null,
};

pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
    namespace: ?[]const u8 = null,
};

pub const DocumentType = struct {
    name: []const u8,
    public_id: ?[]const u8 = null,
    system_id: ?[]const u8 = null,
};

pub fn getDocument(dom: Dom, id: DocumentId) ?*Document {
    if (@intFromEnum(id) > dom.documents.items.len) return null;
    return &dom.documents.items[@intFromEnum(id)];
}
pub fn getElement(dom: Dom, id: ElementId) ?*Element {
    if (@intFromEnum(id) > dom.elements.items.len) return null;
    return &dom.elements.items[@intFromEnum(id)];
}

pub fn getText(dom: Dom, id: TextId) ?*Text {
    if (@intFromEnum(id) > dom.texts.items.len) return null;
    return &dom.texts.items[@intFromEnum(id)];
}

pub fn getComment(dom: Dom, id: CommentId) ?*Comment {
    if (@intFromEnum(id) > dom.comments.items.len) return null;
    return &dom.comments.items[@intFromEnum(id)];
}

pub fn getAttribute(dom: Dom, id: AttributeId) ?*Attribute {
    if (@intFromEnum(id) > dom.attributes.items.len) return null;
    return &dom.attributes.items[@intFromEnum(id)];
}

pub fn getDocumentType(dom: Dom, id: DocumentTypeId) ?*DocumentType {
    if (@intFromEnum(id) > dom.document_types.items.len) return null;
    return &dom.document_types.items[@intFromEnum(id)];
}

pub fn createDocument(dom: *Dom) !DocumentId {
    try dom.documents.append(dom.allocator, .{});
    return @enumFromInt(dom.documents.items.len - 1);
}

pub fn createElement(dom: *Dom, tag_name: []const u8) !ElementId {
    const interned_tag_name = try dom.internString(tag_name);
    try dom.elements.append(dom.allocator, .{ .tag_name = interned_tag_name });
    return @enumFromInt(dom.elements.items.len - 1);
}

pub fn createText(dom: *Dom, data: []const u8) !TextId {
    const interned_data = try dom.internString(data);
    try dom.texts.append(dom.allocator, .{ .data = interned_data });
    return @enumFromInt(dom.texts.items.len - 1);
}

pub fn createComment(dom: *Dom, data: []const u8) !CommentId {
    const interned_data = try dom.internString(data);
    try dom.comments.append(dom.allocator, .{ .data = interned_data });
    return @enumFromInt(dom.comments.items.len - 1);
}

pub fn createAttribute(dom: *Dom, name: []const u8, value: []const u8) !AttributeId {
    const interned_name = try dom.internString(name);
    const interned_value = try dom.internString(value);
    try dom.attributes.append(dom.allocator, .{ .name = interned_name, .value = interned_value });
    return @enumFromInt(dom.attributes.items.len - 1);
}

pub fn createDocumentType(dom: *Dom, name: []const u8) !DocumentTypeId {
    const interned_name = try dom.internString(name);
    try dom.document_types.append(dom.allocator, .{ .name = interned_name });
    return @enumFromInt(dom.document_types.items.len - 1);
}

pub fn appendChild(dom: *Dom, parent_id: ElementId, child: ContentNode) !void {
    switch (child) {
        .element => |child_id| {
            const child_element = dom.getElement(child_id).?;
            child_element.parent = parent_id;
        },
        .text => |child_id| {
            const child_text = dom.getText(child_id).?;
            child_text.parent = parent_id;
        },
        .comment => |child_id| {
            const child_comment = dom.getComment(child_id).?;
            child_comment.parent = parent_id;
        },
    }

    const parent = dom.getElement(parent_id).?;

    try parent.children.append(dom.allocator, child);
}

pub fn appendToDocument(dom: *Dom, document_id: DocumentId, child: DocumentChild) !void {
    const document = dom.getDocument(document_id).?;

    switch (child) {
        .element => |element_id| {
            std.debug.assert(document.element == null);
            document.element = element_id;
        },
        .document_type => |document_type_id| {
            std.debug.assert(document.document_type == null);
            document.document_type = document_type_id;
        },
        else => {},
    }

    try document.children.append(dom.allocator, child);
}

pub fn printDocument(dom: Dom, document_id: DocumentId, writer: anytype) !void {
    const document = dom.getDocument(document_id).?;

    for (document.children.items) |child| {
        switch (child) {
            .document_type => |document_type_id| {
                const document_type = dom.getDocumentType(document_type_id).?;
                try writer.print("<!DOCTYPE {s}>\n", .{document_type.name}); // TODO: print other things
            },
            .element => |element_id| {
                try dom.printElement(element_id, writer, 0);
            },
            .comment => |comment_id| {
                const comment = dom.getComment(comment_id).?;
                try writer.print("<!-- {s} -->\n", .{comment.data});
            },
        }
    }
}

fn printElement(dom: Dom, element_id: ElementId, writer: anytype, indent: usize) !void {
    const element = dom.getElement(element_id).?;

    for (0..indent) |_| {
        try writer.writeAll("  ");
    }

    try writer.print("<{s}", .{element.tag_name});

    for (element.attributes.items) |attribute_id| {
        const attribute = dom.getAttribute(attribute_id).?;
        try writer.print(" {s}=\"{s}\"", .{ attribute.name, attribute.value });
    }

    if (element.children.items.len == 0) {
        try writer.writeAll(" />\n");
    } else {
        try writer.writeAll(">");

        var has_element_children = false;
        for (element.children.items) |child| {
            switch (child) {
                .element => {
                    if (!has_element_children) {
                        try writer.writeAll("\n");
                        has_element_children = true;
                    }

                    try dom.printElement(child.element, writer, indent + 1);
                },
                .text => {
                    const text = dom.getText(child.text).?;
                    try writer.writeAll(text.data);
                },
                .comment => {
                    const comment = dom.getComment(child.comment).?;
                    try writer.print("<!-- {s} -->", .{comment.data});
                },
            }
        }

        if (has_element_children) {
            for (0..indent) |_| {
                try writer.writeAll("  ");
            }
        }

        try writer.print("</{s}>\n", .{element.tag_name});
    }
}
