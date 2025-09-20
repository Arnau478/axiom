const Browser = @This();

const std = @import("std");
const glfw = @import("glfw");
const engine = @import("engine");
const vulkan = @import("vulkan");

pub const ViewChildProcess = @import("Browser/ViewChildProcess.zig");

pub const Tab = struct {
    view_process: ViewChildProcess,

    fn close(tab: *Tab) void {
        tab.view_process.kill();
    }
};

allocator: std.mem.Allocator,
window: *glfw.Window,
renderer: vulkan.Renderer,
tabs: std.ArrayList(Tab),
current_tab_index: usize,

// TODO: Proper window sizing
const window_width = 500;
const window_height = 400;

pub fn init(allocator: std.mem.Allocator) !Browser {
    try glfw.init();

    glfw.WindowHint.set(.client_api, .no_api);
    glfw.WindowHint.set(.resizable, false);

    const window = try glfw.Window.create(window_width, window_height, "axiom", null);

    var browser: Browser = .{
        .allocator = allocator,
        .window = window,
        .renderer = try .init(.{
            .allocator = allocator,
            .loader = @extern(*const vulkan.GetInstanceProcAddressFunction, .{ .name = "glfwGetInstanceProcAddress" }),
            .extensions = try glfw.getRequiredInstanceExtensions(),
            .application_name = "axiom",
            .createWindowSurface = @extern(*const vulkan.CreateWindowSurfaceFunction, .{ .name = "glfwCreateWindowSurface" }),
            .create_window_surface_ctx = window,
            .window_width = window_width,
            .window_height = window_height,
        }),
        .tabs = .empty,
        .current_tab_index = 0,
    };

    _ = try browser.newTab();

    return browser;
}

pub fn deinit(browser: *Browser) void {
    for (browser.tabs.items) |*tab| {
        tab.close();
    }
    browser.tabs.deinit(browser.allocator);

    browser.renderer.deinit();

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
    while (!browser.window.shouldClose()) {
        glfw.pollEvents();

        if (browser.tabs.items.len == 0) break;

        try browser.currentTab().view_process.send(.{ .resize_viewport = .{ .width = window_width, .height = window_height } });

        const draw_list = try browser.currentTab().view_process.recv(browser.allocator, .new_frame);
        defer browser.allocator.free(draw_list);

        try browser.renderer.drawFrame(draw_list);
    }
}
