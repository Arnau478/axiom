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
            const about_pages = std.StaticStringMap([]const u8).initComptime(&.{
                .{
                    "blank",
                    \\<!DOCTYPE html>
                    \\<html>
                    \\  <head>
                    \\  </head>
                    \\  <body style="background-color:gray">
                    \\    <foo-a style="display:block;margin-top:10px;margin-right:10px;margin-bottom:10px;margin-left:10px;background-color:red;">
                    \\      <foo-b style="display:block;margin-top:10px;margin-right:10px;margin-bottom:10px;margin-left:10px;background-color:green;">
                    \\        <foo-c style="display:block;margin-top:10px;margin-right:10px;margin-bottom:10px;margin-left:10px;background-color:blue;height:100px;">
                    \\        </foo-c>
                    \\        <foo-c style="display:block;margin-top:10px;margin-right:10px;margin-bottom:10px;margin-left:10px;background-color:blue;height:100px;">
                    \\        </foo-c>
                    \\      </foo-b>
                    \\    </foo-a>
                    \\  </body>
                    \\</html>
                },
            });

            const html_source = try engine.fetch.fetch(view_process.url, about_pages);

            const update_start_time = std.time.milliTimestamp();

            var dom = engine.Dom.init(view_process.allocator);
            defer dom.deinit();

            const document = try dom.createDocument();

            try engine.html.parse(view_process.allocator, &dom, document, html_source);

            try dom.printDocument(document, std.io.getStdErr().writer());

            const style_tree = try engine.style.style(view_process.allocator, dom, document, user_agent_stylesheet);
            defer style_tree.deinit();

            var box_tree = try engine.layout.generateBox(view_process.allocator, style_tree, style_tree.root);
            defer box_tree.deinit(view_process.allocator);

            try box_tree.printTree(dom, std.io.getStdErr().writer().any());

            engine.layout.reflow(box_tree, .{
                .width = @floatFromInt(view_process.viewport_width),
                .height = @floatFromInt(view_process.viewport_height),
            });

            const draw_list = try engine.paint.paint(view_process.allocator, box_tree);
            defer view_process.allocator.free(draw_list);

            const update_end_time = std.time.milliTimestamp();
            const update_time = update_end_time - update_start_time;

            std.log.debug("Update time: {d}ms", .{update_time});

            try stdout.writeByte(0x06);
            try serialize.write(ipc.Response, .{ .new_frame = draw_list }, stdout.any());
        }
    }
}
