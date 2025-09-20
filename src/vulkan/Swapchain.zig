const Swapchain = @This();

const std = @import("std");
const vk = @import("vk");
const GraphicsContext = @import("GraphicsContext.zig");

const log = std.log.scoped(.vulkan);

handle: vk.SwapchainKHR,
gc: *const GraphicsContext,
surface_format: vk.SurfaceFormatKHR,
present_mode: vk.PresentModeKHR,
extent: vk.Extent2D,
swap_images: []Image,
image_index: u32,
next_image_acquired: vk.Semaphore,

pub const Image = struct {
    handle: vk.Image,
    view: vk.ImageView,
    image_acquired: vk.Semaphore,
    render_finished: vk.Semaphore,
    frame_fence: vk.Fence,

    pub fn init(gc: *const GraphicsContext, handle: vk.Image, format: vk.Format) !Image {
        const view = try gc.device.createImageView(&.{
            .image = handle,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer gc.device.destroyImageView(view, null);

        const image_acquired = try gc.device.createSemaphore(&.{}, null);
        errdefer gc.device.destroySemaphore(image_acquired, null);

        const render_finished = try gc.device.createSemaphore(&.{}, null);
        errdefer gc.device.destroySemaphore(render_finished, null);

        const frame_fence = try gc.device.createFence(&.{ .flags = .{ .signaled_bit = true } }, null);
        errdefer gc.device.destroyFence(frame_fence, null);

        return .{
            .handle = handle,
            .view = view,
            .image_acquired = image_acquired,
            .render_finished = render_finished,
            .frame_fence = frame_fence,
        };
    }

    pub fn deinit(image: Image, gc: *const GraphicsContext) void {
        image.waitForFence(gc) catch return;
        gc.device.destroyFence(image.frame_fence, null);
        gc.device.destroySemaphore(image.render_finished, null);
        gc.device.destroySemaphore(image.image_acquired, null);
        gc.device.destroyImageView(image.view, null);
    }

    pub fn waitForFence(image: Image, gc: *const GraphicsContext) !void {
        _ = try gc.device.waitForFences(1, @ptrCast(&image.frame_fence), .true, std.math.maxInt(u64));
    }
};

pub fn init(allocator: std.mem.Allocator, gc: *const GraphicsContext, extent: vk.Extent2D) !Swapchain {
    return try initRecycle(allocator, gc, extent, .null_handle);
}

pub fn initRecycle(allocator: std.mem.Allocator, gc: *const GraphicsContext, specified_extent: vk.Extent2D, old_handle: vk.SwapchainKHR) !Swapchain {
    const capabilities = try gc.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(gc.physical_device, gc.surface);
    const extent = findActualExtent(capabilities, specified_extent);

    if (extent.width == 0 or extent.height == 0) return error.InvalidSurfaceDimensions;

    const surface_format = try findSurfaceFormat(gc, allocator);
    const present_mode = try findPresentMode(gc, allocator);

    var image_count = capabilities.min_image_count + 1;
    if (capabilities.max_image_count > 0) {
        image_count = @min(image_count, capabilities.max_image_count);
    }

    const queue_family_indices = [_]u32{ gc.graphics_queue.family, gc.present_queue.family };

    const handle = gc.device.createSwapchainKHR(&.{
        .surface = gc.surface,
        .min_image_count = image_count,
        .image_format = surface_format.format,
        .image_color_space = surface_format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
        .image_sharing_mode = if (gc.graphics_queue.family != gc.present_queue.family) .concurrent else .exclusive,
        .queue_family_index_count = queue_family_indices.len,
        .p_queue_family_indices = &queue_family_indices,
        .pre_transform = capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = present_mode,
        .clipped = .true,
        .old_swapchain = old_handle,
    }, null) catch return error.SwapchainCreationFailed;
    errdefer gc.device.destroySwapchainKHR(handle, null);

    if (old_handle != .null_handle) {
        gc.device.destroySwapchainKHR(old_handle, null);
    }

    const swap_images = try initSwapImages(gc, handle, surface_format.format, allocator);
    errdefer {
        for (swap_images) |image| image.deinit(gc);
        allocator.free(swap_images);
    }

    var next_image_acquired = try gc.device.createSemaphore(&.{}, null);
    errdefer gc.device.destroySemaphore(next_image_acquired, null);

    const acquire_result = try gc.device.acquireNextImageKHR(handle, std.math.maxInt(u64), next_image_acquired, .null_handle);

    if (acquire_result.result == .not_ready or acquire_result.result == .timeout) return error.ImageAcquireFailed;

    std.mem.swap(vk.Semaphore, &swap_images[acquire_result.image_index].image_acquired, &next_image_acquired);

    return .{
        .handle = handle,
        .gc = gc,
        .surface_format = surface_format,
        .present_mode = present_mode,
        .extent = extent,
        .swap_images = swap_images,
        .image_index = acquire_result.image_index,
        .next_image_acquired = next_image_acquired,
    };
}

fn deinitExceptSwapchain(swapchain: Swapchain, allocator: std.mem.Allocator) void {
    for (swapchain.swap_images) |image| image.deinit(swapchain.gc);
    allocator.free(swapchain.swap_images);
    swapchain.gc.device.destroySemaphore(swapchain.next_image_acquired, null);
}

pub fn waitForAllFences(swapchain: Swapchain) !void {
    for (swapchain.swap_images) |image| image.waitForFence(swapchain.gc) catch {};
}

pub fn deinit(swapchain: Swapchain, allocator: std.mem.Allocator) void {
    if (swapchain.handle == .null_handle) return;
    swapchain.deinitExceptSwapchain(allocator);
    swapchain.gc.device.destroySwapchainKHR(swapchain.handle, null);
}

pub fn recreate(swapchain: *Swapchain, allocator: std.mem.Allocator, new_extent: vk.Extent2D) !void {
    const gc = swapchain.gc;
    const old_handle = swapchain.handle;
    swapchain.deinitExceptSwapchain(allocator);

    swapchain.handle = .null_handle;
    swapchain.* = Swapchain.initRecycle(allocator, gc, new_extent, old_handle) catch |err| switch (err) {
        error.SwapchainCreationFailed => {
            gc.device.destroySwapchainKHR(old_handle, null);
            return err;
        },
        else => return err,
    };
}

pub fn currentImage(swapchain: Swapchain) *const Image {
    return &swapchain.swap_images[swapchain.image_index];
}

pub const PresentState = enum {
    optimal,
    suboptimal,
};

pub fn present(swapchain: *Swapchain, command_buffer: vk.CommandBuffer) !PresentState {
    const current = swapchain.currentImage();
    try current.waitForFence(swapchain.gc);
    try swapchain.gc.device.resetFences(1, @ptrCast(&current.frame_fence));

    try swapchain.gc.device.queueSubmit(swapchain.gc.graphics_queue.handle, 1, &.{
        .{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current.image_acquired),
            .p_wait_dst_stage_mask = &.{.{ .top_of_pipe_bit = true }},
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&command_buffer),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&current.render_finished),
        },
    }, current.frame_fence);

    _ = try swapchain.gc.device.queuePresentKHR(swapchain.gc.present_queue.handle, &.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&current.render_finished),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&swapchain.handle),
        .p_image_indices = @ptrCast(&swapchain.image_index),
    });

    const acquire_result = try swapchain.gc.device.acquireNextImageKHR(swapchain.handle, std.math.maxInt(u64), swapchain.next_image_acquired, .null_handle);

    std.mem.swap(vk.Semaphore, &swapchain.swap_images[acquire_result.image_index].image_acquired, &swapchain.next_image_acquired);
    swapchain.image_index = acquire_result.image_index;

    return switch (acquire_result.result) {
        .success => .optimal,
        .suboptimal_khr => .suboptimal,
        else => unreachable,
    };
}

fn findActualExtent(capabilities: vk.SurfaceCapabilitiesKHR, extent: vk.Extent2D) vk.Extent2D {
    if (capabilities.current_extent.width != 0xFFFFFFFF) {
        return capabilities.current_extent;
    } else {
        return .{
            .width = std.math.clamp(extent.width, capabilities.min_image_extent.width, capabilities.max_image_extent.width),
            .height = std.math.clamp(extent.height, capabilities.min_image_extent.height, capabilities.max_image_extent.height),
        };
    }
}

fn findSurfaceFormat(gc: *const GraphicsContext, allocator: std.mem.Allocator) !vk.SurfaceFormatKHR {
    const preferred: vk.SurfaceFormatKHR = .{
        .format = .b8g8r8a8_srgb,
        .color_space = .srgb_nonlinear_khr,
    };

    const surface_formats = try gc.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(gc.physical_device, gc.surface, allocator);
    defer allocator.free(surface_formats);

    for (surface_formats) |format| {
        if (std.meta.eql(format, preferred)) {
            return preferred;
        }
    }

    return surface_formats[0];
}

fn findPresentMode(gc: *const GraphicsContext, allocator: std.mem.Allocator) !vk.PresentModeKHR {
    const preferred = [_]vk.PresentModeKHR{
        .mailbox_khr,
        .immediate_khr,
    };

    const present_modes = try gc.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(gc.physical_device, gc.surface, allocator);
    defer allocator.free(present_modes);

    for (preferred) |mode| {
        if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, mode) != null) {
            return mode;
        }
    }

    return .fifo_khr;
}

fn initSwapImages(gc: *const GraphicsContext, swapchain: vk.SwapchainKHR, format: vk.Format, allocator: std.mem.Allocator) ![]Image {
    const images = try gc.device.getSwapchainImagesAllocKHR(swapchain, allocator);
    defer allocator.free(images);

    const swap_images = try allocator.alloc(Image, images.len);
    errdefer allocator.free(swap_images);

    var i: usize = 0;
    errdefer for (swap_images[0..i]) |image| image.deinit(gc);

    for (images) |image| {
        swap_images[i] = try .init(gc, image, format);
        i += 1;
    }

    return swap_images;
}
