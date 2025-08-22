const std = @import("std");
const engine = @import("engine");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const user_agent_stylesheet = try engine.style.css.parseStylesheet(allocator, @embedFile("ua.css"));
    defer user_agent_stylesheet.deinit(allocator);

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

    const div_element_style_attribute = try dom.createAttribute("style", "margin-left: 20px; margin-right: 20px");
    try dom.addAttribute(div_element, div_element_style_attribute);

    try dom.printDocument(document, std.io.getStdOut().writer());

    for (dom.elements.items, 0..) |element, i| {
        std.log.debug("{d} -> {s}", .{ i, element.tag_name });
    }

    const style_tree = try engine.style.style(allocator, dom, document, user_agent_stylesheet);
    defer style_tree.deinit();

    var layout_tree = try engine.layout.LayoutTree.generate(allocator, style_tree);
    defer layout_tree.deinit();

    engine.layout.flow.reflow(layout_tree, 300);

    for (layout_tree.nodes.items) |node| {
        std.log.debug("{}", .{node.box});
    }
}
