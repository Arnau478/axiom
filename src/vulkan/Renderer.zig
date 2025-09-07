const Renderer = @This();

const std = @import("std");
const vulkan = @import("vulkan.zig");
const GraphicsContext = @import("GraphicsContext.zig");
const Swapchain = @import("Swapchain.zig");

allocator: std.mem.Allocator,
gc: *GraphicsContext,
swapchain: Swapchain,

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
    loader: *const vulkan.GetInstanceProcAddressFunction,
    extensions: []const [*:0]const u8,
    application_name: [*:0]const u8,
    createWindowSurface: *const vulkan.CreateWindowSurfaceFunction,
    create_window_surface_ctx: *anyopaque,
    extent_width: u32,
    extent_height: u32,
};

pub fn init(options: InitOptions) !Renderer {
    const gc = try options.allocator.create(GraphicsContext);
    errdefer options.allocator.destroy(gc);

    gc.* = try GraphicsContext.init(.{
        .allocator = options.allocator,
        .loader = options.loader,
        .extensions = options.extensions,
        .application_name = options.application_name,
        .createWindowSurface = options.createWindowSurface,
        .create_window_surface_ctx = options.create_window_surface_ctx,
    });
    errdefer gc.deinit();

    const swapchain = try Swapchain.init(options.allocator, gc, .{ .width = options.extent_width, .height = options.extent_height });
    errdefer swapchain.deinit(options.allocator);

    return .{
        .allocator = options.allocator,
        .gc = gc,
        .swapchain = swapchain,
    };
}

pub fn deinit(renderer: Renderer) void {
    renderer.swapchain.deinit(renderer.allocator);
    renderer.gc.deinit();
    renderer.allocator.destroy(renderer.gc);
}
