const ViewProcess = @This();

const std = @import("std");
const engine = @import("engine");
const serialize = @import("serialize.zig");
const ipc = @import("ipc.zig");

allocator: std.mem.Allocator,
active: bool = false,
url: []const u8,
viewport_width: usize,
viewport_height: usize,

pub fn init(allocator: std.mem.Allocator) !ViewProcess {
    return .{
        .allocator = allocator,
        .url = try allocator.dupe(u8, ""),
        .viewport_width = 0,
        .viewport_height = 0,
    };
}

pub fn deinit(view_process: ViewProcess) void {
    view_process.allocator.free(view_process.url);
}

pub fn run(view_process: *ViewProcess) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    // TODO: Fetch ua.css via IPC
    const user_agent_stylesheet = try engine.style.css.parseStylesheet(view_process.allocator, @embedFile("ua.css"));
    defer user_agent_stylesheet.deinit(view_process.allocator);

    while (true) {
        const syn_byte = try stdin.readByte();
        if (syn_byte != 0x16) std.process.fatal("Invalid request, expected SYN (0x16), got 0x{x:0>2}", .{syn_byte});

        const request = try serialize.read(ipc.Request, view_process.allocator, stdin.any());
        switch (request) {
            .navigate_to_url => |url| {
                errdefer view_process.allocator.free(url);

                view_process.allocator.free(view_process.url);
                view_process.url = url;
            },
            .resize_viewport => |size| {
                view_process.viewport_width = size.width;
                view_process.viewport_height = size.height;
            },
            .activate => {
                view_process.active = true;
            },
        }

        if (view_process.active) {
            const update_start_time = std.time.milliTimestamp();

            var dom = engine.Dom.init(view_process.allocator);
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

            const style_tree = try engine.style.style(view_process.allocator, dom, document, user_agent_stylesheet);
            defer style_tree.deinit();

            var layout_tree = try engine.layout.LayoutTree.generate(view_process.allocator, style_tree);
            defer layout_tree.deinit();

            engine.layout.reflow(layout_tree, @floatFromInt(view_process.viewport_width));

            const draw_list = try engine.paint.paint(view_process.allocator, layout_tree);
            defer view_process.allocator.free(draw_list);

            const update_end_time = std.time.milliTimestamp();
            const update_time = update_end_time - update_start_time;

            std.log.debug("Update time: {d}ms", .{update_time});

            try stdout.writeByte(0x06);
            try serialize.write(ipc.Response, .{ .new_frame = draw_list }, stdout.any());
        }
    }
}
