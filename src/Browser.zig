const Browser = @This();

const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");
const engine = @import("engine");

pub const ViewChildProcess = @import("Browser/ViewChildProcess.zig");

pub const Tab = struct {
    view_process: ViewChildProcess,

    fn close(tab: *Tab) void {
        tab.view_process.kill();
    }
};

allocator: std.mem.Allocator,
window: *glfw.Window,
gl_procs: gl.ProcTable,
tabs: std.ArrayListUnmanaged(Tab),
current_tab_index: usize,

pub fn init(allocator: std.mem.Allocator) !Browser {
    try glfw.init();
    const window = try glfw.Window.create(600, 600, "axiom", null);

    var browser: Browser = .{
        .allocator = allocator,
        .window = window,
        .gl_procs = undefined,
        .tabs = .empty,
        .current_tab_index = 0,
    };

    glfw.makeContextCurrent(browser.window);
    if (!browser.gl_procs.init(glfw.getProcAddress)) @panic("TODO");
    glfw.swapInterval(1);

    _ = try browser.newTab();

    return browser;
}

pub fn deinit(browser: *Browser) void {
    for (browser.tabs.items) |*tab| {
        tab.close();
    }
    browser.tabs.deinit(browser.allocator);

    browser.window.destroy();
    glfw.terminate();
}

fn newTab(browser: *Browser) !usize {
    try browser.tabs.append(browser.allocator, .{ .view_process = try .init(browser.allocator) });
    const idx = browser.tabs.items.len - 1;

    try browser.tabs.items[idx].view_process.send(.{ .navigate_to_url = "about:blank" });
    try browser.tabs.items[idx].view_process.send(.activate);

    return idx;
}

fn currentTab(browser: *Browser) *Tab {
    return &browser.tabs.items[browser.current_tab_index];
}

pub fn run(browser: *Browser) !void {
    glfw.makeContextCurrent(browser.window);
    defer glfw.makeContextCurrent(null);
    gl.makeProcTableCurrent(&browser.gl_procs);
    defer gl.makeProcTableCurrent(null);

    while (!browser.window.shouldClose()) {
        glfw.pollEvents();

        if (browser.tabs.items.len == 0) break;

        const window_size = browser.window.getFramebufferSize();
        try browser.currentTab().view_process.send(.{ .resize_viewport = .{ .width = @intCast(window_size[0]), .height = @intCast(window_size[1]) } });

        const draw_list = try browser.currentTab().view_process.recv(browser.allocator, .new_frame);
        defer browser.allocator.free(draw_list);

        const draw_start_time = std.time.milliTimestamp();
        engine.render.draw(draw_list, @floatFromInt(window_size[0]), @floatFromInt(window_size[1]));
        const draw_end_time = std.time.milliTimestamp();
        const draw_time = draw_end_time - draw_start_time;
        std.log.debug("Draw time: {d}ms", .{draw_time});

        browser.window.swapBuffers();
    }
}
