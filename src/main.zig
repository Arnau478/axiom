const std = @import("std");
const engine = @import("engine");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dom = engine.Dom.init(allocator);
    defer dom.deinit();

    const document = try dom.createDocument();

    const doctype = try dom.createDocumentType("html");
    try dom.appendToDocument(document, .{ .document_type = doctype });

    const html_element = try dom.createElement("html");
    try dom.appendToDocument(document, .{ .element = html_element });
    const head_element = try dom.createElement("head");
    try dom.appendChild(html_element, .{ .element = head_element });
    const body_element = try dom.createElement("body");
    try dom.appendChild(html_element, .{ .element = body_element });

    const title_element = try dom.createElement("title");
    try dom.appendChild(head_element, .{ .element = title_element });
    const title_text = try dom.createText("Hello world");
    try dom.appendChild(title_element, .{ .text = title_text });

    const div_element = try dom.createElement("div");
    try dom.appendChild(body_element, .{ .element = div_element });

    const div_element_style_attribute = try dom.createAttribute("style", "margin-top: 3px; margin-bottom: 10%");
    try dom.addAttribute(div_element, div_element_style_attribute);

    try dom.printDocument(document, std.io.getStdOut().writer());

    const style_tree = try engine.style.style(allocator, dom, document);
    defer style_tree.deinit();

    for (style_tree.nodes) |node| {
        std.log.debug("{}", .{node});
    }

    for (style_tree.computed_styles) |computed_style| {
        std.log.debug("{}", .{computed_style});
    }
}
