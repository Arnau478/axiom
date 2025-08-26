const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");
const engine = @import("engine");
const serialize = @import("serialize.zig");

const Request = union(enum(u8)) {
    navigate_to_url: []const u8,
    resize_surface: struct {
        width: usize,
        height: usize,
    },
};

const Response = union(enum(u8)) {
    new_frame: []const engine.render.Command,
};

const ViewChildProcess = struct {
    child: std.process.Child,

    pub fn init(allocator: std.mem.Allocator) !ViewChildProcess {
        var process: ViewChildProcess = .{
            .child = .init(&.{ "/proc/self/exe", "--view-process" }, allocator),
        };

        process.child.stdin_behavior = .Pipe;
        process.child.stdout_behavior = .Pipe;
        process.child.stderr_behavior = .Inherit;

        try process.child.spawn();

        std.log.debug("Created view process {d}", .{process.child.id});

        return process;
    }

    pub fn kill(process: *ViewChildProcess) void {
        std.log.debug("Killing view process {d}", .{process.child.id});

        _ = process.child.kill() catch {};
    }

    fn send(process: ViewChildProcess, request: Request) error{RequestError}!void {
        process.child.stdin.?.writer().writeByte(0x16) catch return error.RequestError; // SYN

        serialize.write(Request, request, process.child.stdin.?.writer().any()) catch return error.RequestError;
    }

    fn recv(process: ViewChildProcess, allocator: std.mem.Allocator, comptime response_type: std.meta.Tag(Response)) error{InvalidResponse}!@FieldType(Response, @tagName(response_type)) {
        const ack_byte = process.child.stdout.?.reader().readByte() catch return error.InvalidResponse;
        if (ack_byte != 0x06) return error.InvalidResponse;
        const response = serialize.read(Response, allocator, process.child.stdout.?.reader().any()) catch return error.InvalidResponse;

        if (std.meta.activeTag(response) != response_type) return error.InvalidResponse;
        return @field(response, @tagName(response_type));
    }
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // TODO: Proper argument parsing
    if (args.len == 1) {
        try glfw.init();
        defer glfw.terminate();

        const window = try glfw.Window.create(600, 600, "axiom", null);
        defer window.destroy();

        glfw.makeContextCurrent(window);
        glfw.swapInterval(1);

        var gl_procs: gl.ProcTable = undefined;
        if (!gl_procs.init(glfw.getProcAddress)) @panic("TODO");
        gl.makeProcTableCurrent(&gl_procs);
        defer gl.makeProcTableCurrent(null);

        var view_process = try ViewChildProcess.init(allocator);
        defer view_process.kill();
        try view_process.send(.{ .navigate_to_url = "https://example.org" });

        while (!window.shouldClose()) {
            glfw.pollEvents();

            const window_size = window.getFramebufferSize();
            try view_process.send(.{ .resize_surface = .{ .width = @intCast(window_size[0]), .height = @intCast(window_size[1]) } });

            const draw_list = try view_process.recv(allocator, .new_frame);
            defer allocator.free(draw_list);

            const draw_start_time = std.time.milliTimestamp();
            engine.render.draw(draw_list, @floatFromInt(window_size[0]), @floatFromInt(window_size[1]));
            const draw_end_time = std.time.milliTimestamp();
            const draw_time = draw_end_time - draw_start_time;
            std.log.debug("Draw time: {d}ms", .{draw_time});

            window.swapBuffers();
        }
    } else if (args.len == 2 and std.mem.eql(u8, args[1], "--view-process")) {
        std.log.debug("View process started", .{});

        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();

        const user_agent_stylesheet = try engine.style.css.parseStylesheet(allocator, @embedFile("ua.css"));
        defer user_agent_stylesheet.deinit(allocator);

        var url: []const u8 = try allocator.dupe(u8, "about:blank");
        defer allocator.free(url);

        var surface_width: usize = 0;
        var surface_height: usize = 0;

        while (true) {
            const syn_byte = try stdin.readByte();
            if (syn_byte != 0x16) std.process.fatal("Invalid request, expected SYN (0x16), got 0x{x:0>2}", .{syn_byte});

            const request = try serialize.read(Request, allocator, stdin.any());
            switch (request) {
                .navigate_to_url => |new_url| {
                    allocator.free(url);
                    url = new_url;
                },
                .resize_surface => |size| {
                    surface_width = size.width;
                    surface_height = size.height;
                },
            }

            const update_start_time = std.time.milliTimestamp();

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

            const style_tree = try engine.style.style(allocator, dom, document, user_agent_stylesheet);
            defer style_tree.deinit();

            var layout_tree = try engine.layout.LayoutTree.generate(allocator, style_tree);
            defer layout_tree.deinit();

            engine.layout.reflow(layout_tree, @floatFromInt(surface_width));

            const draw_list = try engine.paint.paint(allocator, layout_tree);
            defer allocator.free(draw_list);

            const update_end_time = std.time.milliTimestamp();
            const update_time = update_end_time - update_start_time;

            std.log.debug("Update time: {d}ms", .{update_time});

            try stdout.writeByte(0x06);
            try serialize.write(Response, .{ .new_frame = draw_list }, stdout.any());
        }
    }
}
