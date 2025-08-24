const std = @import("std");
const sdl3 = @import("sdl3");
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

    const div_element_style_attribute = try dom.createAttribute("style", "margin-left: 20px; margin-right: 20px; height: 100px; background-color: red");
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

    const draw_list = try engine.paint.paint(allocator, layout_tree);
    defer allocator.free(draw_list);

    std.log.debug("{any}", .{draw_list});

    const renderer = engine.Renderer.init(allocator, .{});
    defer renderer.deinit();

    const surface = try renderer.createSurface(300, 300);
    defer surface.deinit();

    surface.draw(draw_list);

    defer sdl3.shutdown();

    const sdl_init_flags: sdl3.InitFlags = .{ .video = true };
    try sdl3.init(sdl_init_flags);
    defer sdl3.quit(sdl_init_flags);

    const window = try sdl3.video.Window.init("axiom", 300, 300, .{});
    defer window.deinit();

    const sdl_renderer = try sdl3.render.Renderer.init(window, null);
    defer sdl_renderer.deinit();

    const texture = try sdl3.render.Texture.init(sdl_renderer, .array_rgb_24, .streaming, 300, 300);
    defer texture.deinit();

    var fps_capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = 60 } };
    while (true) {
        const dt = fps_capper.delay();
        _ = dt;

        const pixels = try surface.readPixelsAlloc(allocator, .rgb);
        defer allocator.free(pixels);

        try texture.update(null, pixels.ptr, 300 * 3);

        try sdl_renderer.clear();
        try sdl_renderer.renderTexture(texture, null, null);
        try sdl_renderer.present();

        if (sdl3.events.poll()) |event| {
            switch (event) {
                .quit => break,
                .terminating => break,
                else => {},
            }
        }
    }
}
