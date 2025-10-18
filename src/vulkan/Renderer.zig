const Renderer = @This();

const std = @import("std");
const engine = @import("engine");
const vk = @import("vk");
const vulkan = @import("vulkan.zig");
const GraphicsContext = @import("GraphicsContext.zig");
const Swapchain = @import("Swapchain.zig");

const vert_spv align(4) = @embedFile("vert_spv").*;
const frag_spv align(4) = @embedFile("frag_spv").*;

const Vertex = struct {
    const binding_description: vk.VertexInputBindingDescription = .{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    const attribute_description: [3]vk.VertexInputAttributeDescription = .{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "color"),
        },
        .{
            .binding = 0,
            .location = 2,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "tex_coord"),
        },
    };

    pos: [2]f32,
    color: [3]f32,
    tex_coord: [2]f32,
};

const PushConstants = struct {
    use_texture: u32,
};

allocator: std.mem.Allocator,
gc: *GraphicsContext,
swapchain: Swapchain,
pipeline_layout: vk.PipelineLayout,
render_pass: vk.RenderPass,
pipeline: vk.Pipeline,
framebuffers: []vk.Framebuffer,
command_pool: vk.CommandPool,
command_buffer: vk.CommandBuffer,
descriptor_pool: vk.DescriptorPool,
descriptor_set_layout: vk.DescriptorSetLayout,
sampler: vk.Sampler,

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
    loader: *const vulkan.GetInstanceProcAddressFunction,
    extensions: []const [*:0]const u8,
    application_name: [*:0]const u8,
    createWindowSurface: *const vulkan.CreateWindowSurfaceFunction,
    create_window_surface_ctx: *anyopaque,
    window_width: u32,
    window_height: u32,
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

    const swapchain = try Swapchain.init(options.allocator, gc, .{ .width = options.window_width, .height = options.window_height });
    errdefer swapchain.deinit(options.allocator);

    const descriptor_set_layout = try createDescriptorSetLayout(gc);
    errdefer gc.device.destroyDescriptorSetLayout(descriptor_set_layout, null);

    const pipeline_layout = try createPipelineLayout(gc, descriptor_set_layout);
    errdefer gc.device.destroyPipelineLayout(pipeline_layout, null);

    const render_pass = try createRenderPass(gc, swapchain);
    errdefer gc.device.destroyRenderPass(render_pass, null);

    const pipeline = try createPipeline(gc, pipeline_layout, render_pass);
    errdefer gc.device.destroyPipeline(pipeline, null);

    const framebuffers = try createFramebuffers(gc, options.allocator, render_pass, swapchain);
    errdefer options.allocator.free(framebuffers);
    errdefer for (framebuffers) |fb| gc.device.destroyFramebuffer(fb, null);

    const command_pool = try createCommandPool(gc, gc.graphics_queue.family);
    errdefer gc.device.destroyCommandPool(command_pool, null);

    var command_buffer: vk.CommandBuffer = undefined;
    try gc.device.allocateCommandBuffers(&.{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&command_buffer));

    const descriptor_pool = try createDescriptorPool(gc);
    errdefer gc.device.destroyDescriptorPool(descriptor_pool, null);

    const sampler = try createSampler(gc);
    errdefer gc.device.destroySampler();

    return .{
        .allocator = options.allocator,
        .gc = gc,
        .swapchain = swapchain,
        .pipeline_layout = pipeline_layout,
        .render_pass = render_pass,
        .pipeline = pipeline,
        .framebuffers = framebuffers,
        .command_pool = command_pool,
        .command_buffer = command_buffer,
        .descriptor_pool = descriptor_pool,
        .descriptor_set_layout = descriptor_set_layout,
        .sampler = sampler,
    };
}

pub fn deinit(renderer: Renderer) void {
    renderer.gc.device.destroySampler(renderer.sampler, null);
    renderer.gc.device.destroyDescriptorPool(renderer.descriptor_pool, null);
    renderer.gc.device.destroyCommandPool(renderer.command_pool, null);
    for (renderer.framebuffers) |fb| renderer.gc.device.destroyFramebuffer(fb, null);
    renderer.allocator.free(renderer.framebuffers);
    renderer.gc.device.destroyPipeline(renderer.pipeline, null);
    renderer.gc.device.destroyRenderPass(renderer.render_pass, null);
    renderer.gc.device.destroyPipelineLayout(renderer.pipeline_layout, null);
    renderer.gc.device.destroyDescriptorSetLayout(renderer.descriptor_set_layout, null);
    renderer.swapchain.deinit(renderer.allocator);
    renderer.gc.deinit();
    renderer.allocator.destroy(renderer.gc);
}

fn createDescriptorSetLayout(gc: *const GraphicsContext) !vk.DescriptorSetLayout {
    const bindings = [_]vk.DescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
        },
    };

    return try gc.device.createDescriptorSetLayout(&.{
        .binding_count = bindings.len,
        .p_bindings = &bindings,
    }, null);
}

fn createPipelineLayout(gc: *const GraphicsContext, descriptor_set_layout: vk.DescriptorSetLayout) !vk.PipelineLayout {
    const push_constant_range: vk.PushConstantRange = .{
        .stage_flags = .{ .fragment_bit = true },
        .offset = 0,
        .size = @sizeOf(PushConstants),
    };

    return try gc.device.createPipelineLayout(&.{
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&descriptor_set_layout),
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    }, null);
}

fn createDescriptorPool(gc: *const GraphicsContext) !vk.DescriptorPool {
    const pool_sizes = [_]vk.DescriptorPoolSize{
        .{
            .type = .combined_image_sampler,
            .descriptor_count = 256, // TODO
        },
    };

    return try gc.device.createDescriptorPool(&.{
        .flags = .{ .free_descriptor_set_bit = true },
        .max_sets = 256, // TODO
        .pool_size_count = pool_sizes.len,
        .p_pool_sizes = &pool_sizes,
    }, null);
}

fn createSampler(gc: *const GraphicsContext) !vk.Sampler {
    return try gc.device.createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .anisotropy_enable = .false,
        .max_anisotropy = 1.0,
        .border_color = .int_opaque_black,
        .unnormalized_coordinates = .false,
        .compare_enable = .false,
        .compare_op = .always,
        .mipmap_mode = .linear,
        .mip_lod_bias = 0.0,
        .min_lod = 0.0,
        .max_lod = 0.0,
    }, null);
}

fn createRenderPass(gc: *const GraphicsContext, swapchain: Swapchain) !vk.RenderPass {
    const color_attachment: vk.AttachmentDescription = .{
        .format = swapchain.surface_format.format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref: vk.AttachmentReference = .{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass: vk.SubpassDescription = .{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment_ref),
    };

    return try gc.device.createRenderPass(&.{
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_attachment),
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
    }, null);
}

fn createShaderModule(gc: *const GraphicsContext, spv: []align(4) const u8) !vk.ShaderModule {
    return try gc.device.createShaderModule(&.{
        .code_size = spv.len,
        .p_code = @ptrCast(spv.ptr),
    }, null);
}

fn createPipeline(gc: *const GraphicsContext, layout: vk.PipelineLayout, render_pass: vk.RenderPass) !vk.Pipeline {
    const vert_module = try createShaderModule(gc, &vert_spv);
    defer gc.device.destroyShaderModule(vert_module, null);
    const frag_module = try createShaderModule(gc, &frag_spv);
    defer gc.device.destroyShaderModule(frag_module, null);

    const shader_stages_info = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex_bit = true },
            .module = vert_module,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = frag_module,
            .p_name = "main",
        },
    };

    const dynamic_state = [_]vk.DynamicState{ .viewport, .scissor };
    const dynamic_info: vk.PipelineDynamicStateCreateInfo = .{
        .flags = .{},
        .dynamic_state_count = dynamic_state.len,
        .p_dynamic_states = &dynamic_state,
    };

    const vertex_input_info: vk.PipelineVertexInputStateCreateInfo = .{
        .vertex_binding_description_count = 1,
        .vertex_attribute_description_count = Vertex.attribute_description.len,
        .p_vertex_binding_descriptions = @ptrCast(&Vertex.binding_description),
        .p_vertex_attribute_descriptions = &Vertex.attribute_description,
    };

    const input_assembly_info: vk.PipelineInputAssemblyStateCreateInfo = .{
        .topology = .triangle_list,
        .primitive_restart_enable = .false,
    };

    const viewport_info: vk.PipelineViewportStateCreateInfo = .{
        .viewport_count = 1,
        .scissor_count = 1,
    };

    const rasterizer_info: vk.PipelineRasterizationStateCreateInfo = .{
        .depth_clamp_enable = .false,
        .rasterizer_discard_enable = .false,
        .polygon_mode = .fill,
        .line_width = 1.0,
        .cull_mode = .{ .back_bit = true },
        .front_face = .clockwise,
        .depth_bias_enable = .false,
        .depth_bias_constant_factor = 0.0,
        .depth_bias_clamp = 0.0,
        .depth_bias_slope_factor = 0.0,
    };

    const multisampling_info: vk.PipelineMultisampleStateCreateInfo = .{
        .sample_shading_enable = .false,
        .rasterization_samples = .{ .@"1_bit" = true },
        .min_sample_shading = 1.0,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    const color_blend_info: vk.PipelineColorBlendStateCreateInfo = .{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = &.{
            .{
                .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
                .blend_enable = .true,
                .src_color_blend_factor = .src_alpha,
                .dst_color_blend_factor = .one_minus_src_alpha,
                .color_blend_op = .add,
                .src_alpha_blend_factor = .one_minus_src_alpha,
                .dst_alpha_blend_factor = .zero,
                .alpha_blend_op = .add,
            },
        },
        .blend_constants = .{ 0.0, 0.0, 0.0, 0.0 },
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try gc.device.createGraphicsPipelines(.null_handle, 1, @ptrCast(&vk.GraphicsPipelineCreateInfo{
        .stage_count = shader_stages_info.len,
        .p_stages = &shader_stages_info,
        .p_vertex_input_state = &vertex_input_info,
        .p_input_assembly_state = &input_assembly_info,
        .p_tessellation_state = null,
        .p_viewport_state = &viewport_info,
        .p_rasterization_state = &rasterizer_info,
        .p_multisample_state = &multisampling_info,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &color_blend_info,
        .p_dynamic_state = &dynamic_info,
        .layout = layout,
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    }), null, @ptrCast(&pipeline));

    return pipeline;
}

fn createFramebuffers(gc: *const GraphicsContext, allocator: std.mem.Allocator, render_pass: vk.RenderPass, swapchain: Swapchain) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swap_images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |fb| gc.device.destroyFramebuffer(fb, null);

    for (framebuffers) |*fb| {
        fb.* = try gc.device.createFramebuffer(&.{
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&swapchain.swap_images[i].view),
            .width = swapchain.extent.width,
            .height = swapchain.extent.height,
            .layers = 1,
        }, null);
        i += 1;
    }

    return framebuffers;
}

fn createCommandPool(gc: *const GraphicsContext, queue_family_index: u32) !vk.CommandPool {
    return try gc.device.createCommandPool(&.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = queue_family_index,
    }, null);
}

const TextureResources = struct {
    image: vk.Image,
    memory: vk.DeviceMemory,
    view: vk.ImageView,
    descriptor_set: vk.DescriptorSet,

    fn deinit(texture_resources: TextureResources, gc: *const GraphicsContext, descriptor_pool: vk.DescriptorPool) void {
        _ = gc.device.freeDescriptorSets(descriptor_pool, 1, @ptrCast(&texture_resources.descriptor_set)) catch {};
        gc.device.destroyImageView(texture_resources.view, null);
        gc.device.destroyImage(texture_resources.image, null);
        gc.device.freeMemory(texture_resources.memory, null);
    }
};

fn createTextureFromData(
    gc: *const GraphicsContext,
    command_buffer: vk.CommandBuffer,
    descriptor_pool: vk.DescriptorPool,
    descriptor_set_layout: vk.DescriptorSetLayout,
    sampler: vk.Sampler,
    texture_data: []const u8,
    width: u32,
    height: u32,
    single_channel: bool,
) !TextureResources {
    const staging_buffer = try gc.device.createBuffer(&.{
        .size = texture_data.len,
        .usage = .{ .transfer_src_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer gc.device.destroyBuffer(staging_buffer, null);

    const staging_mem_reqs = gc.device.getBufferMemoryRequirements(staging_buffer);
    const staging_memory = try gc.allocate(staging_mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    defer gc.device.freeMemory(staging_memory, null);

    try gc.device.bindBufferMemory(staging_buffer, staging_memory, 0);

    const data_ptr = try gc.device.mapMemory(staging_memory, 0, vk.WHOLE_SIZE, .{});
    @memcpy(@as([*]u8, @ptrCast(@alignCast(data_ptr)))[0..texture_data.len], texture_data);
    gc.device.unmapMemory(staging_memory);

    const image = try gc.device.createImage(&.{
        .image_type = .@"2d",
        .format = if (single_channel) .r8_unorm else .r8g8b8a8_srgb,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{ .transfer_dst_bit = true, .sampled_bit = true },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, null);
    errdefer gc.device.destroyImage(image, null);

    const image_mem_reqs = gc.device.getImageMemoryRequirements(image);
    const image_memory = try gc.allocate(image_mem_reqs, .{ .device_local_bit = true });
    errdefer gc.device.freeMemory(image_memory, null);

    try gc.device.bindImageMemory(image, image_memory, 0);

    try gc.device.beginCommandBuffer(command_buffer, &.{ .flags = .{ .one_time_submit_bit = true } });

    gc.device.cmdPipelineBarrier(
        command_buffer,
        .{ .top_of_pipe_bit = true },
        .{ .transfer_bit = true },
        .{},
        0,
        undefined,
        0,
        undefined,
        1,
        @ptrCast(&vk.ImageMemoryBarrier{
            .src_access_mask = .{},
            .dst_access_mask = .{ .transfer_write_bit = true },
            .old_layout = .undefined,
            .new_layout = .transfer_dst_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }),
    );

    const region: vk.BufferImageCopy = .{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_extent = .{ .width = width, .height = height, .depth = 1 },
    };

    gc.device.cmdCopyBufferToImage(command_buffer, staging_buffer, image, .transfer_dst_optimal, 1, @ptrCast(&region));

    gc.device.cmdPipelineBarrier(
        command_buffer,
        .{ .transfer_bit = true },
        .{ .fragment_shader_bit = true },
        .{},
        0,
        undefined,
        0,
        undefined,
        1,
        @ptrCast(&vk.ImageMemoryBarrier{
            .src_access_mask = .{ .transfer_write_bit = true },
            .dst_access_mask = .{ .shader_read_bit = true },
            .old_layout = .transfer_dst_optimal,
            .new_layout = .shader_read_only_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }),
    );

    try gc.device.endCommandBuffer(command_buffer);

    const fence = try gc.device.createFence(&.{}, null);
    defer gc.device.destroyFence(fence, null);

    try gc.device.queueSubmit(gc.graphics_queue.handle, 1, @ptrCast(&vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&command_buffer),
    }), fence);

    _ = try gc.device.waitForFences(1, @ptrCast(&fence), .true, std.math.maxInt(u64));

    const view = try gc.device.createImageView(&.{
        .image = image,
        .view_type = .@"2d",
        .format = if (single_channel) .r8_unorm else .r8g8b8a8_srgb,
        .components = if (single_channel) .{ .r = .one, .g = .one, .b = .one, .a = .r } else .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);
    errdefer gc.device.destroyImageView(view, null);

    var descriptor_set: vk.DescriptorSet = undefined;
    try gc.device.allocateDescriptorSets(&.{
        .descriptor_pool = descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast(&descriptor_set_layout),
    }, @ptrCast(&descriptor_set));
    errdefer _ = gc.device.freeDescriptorSets(descriptor_pool, 1, @ptrCast(&descriptor_set)) catch {};

    const image_info: vk.DescriptorImageInfo = .{
        .sampler = sampler,
        .image_view = view,
        .image_layout = .shader_read_only_optimal,
    };

    gc.device.updateDescriptorSets(1, @ptrCast(&vk.WriteDescriptorSet{
        .dst_set = descriptor_set,
        .dst_binding = 0,
        .dst_array_element = 0,
        .descriptor_count = 1,
        .descriptor_type = .combined_image_sampler,
        .p_image_info = @ptrCast(&image_info),
        .p_buffer_info = undefined,
        .p_texel_buffer_view = undefined,
    }), 0, undefined);

    return .{
        .image = image,
        .memory = image_memory,
        .view = view,
        .descriptor_set = descriptor_set,
    };
}

pub fn drawFrame(renderer: *Renderer, width: usize, height: usize, draw_list: []const engine.paint.Command) !void {
    if (renderer.swapchain.extent.width != width or renderer.swapchain.extent.height != height) {
        try renderer.swapchain.recreate(renderer.allocator, .{ .width = @intCast(width), .height = @intCast(height) });

        for (renderer.framebuffers) |fb| renderer.gc.device.destroyFramebuffer(fb, null);
        renderer.allocator.free(renderer.framebuffers);

        renderer.framebuffers = try createFramebuffers(renderer.gc, renderer.allocator, renderer.render_pass, renderer.swapchain);
    }

    // TODO: Proper support for empty draw_list
    const vertex_buffer_size_per_command = 6;
    const vertex_buffer = try renderer.gc.device.createBuffer(&.{
        .size = @sizeOf(Vertex) * @max(draw_list.len, 1) * vertex_buffer_size_per_command,
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer renderer.gc.device.destroyBuffer(vertex_buffer, null);
    const vertex_buffer_memory_requirements = renderer.gc.device.getBufferMemoryRequirements(vertex_buffer);
    const vertex_buffer_memory = try renderer.gc.allocate(vertex_buffer_memory_requirements, .{ .host_visible_bit = true, .host_coherent_bit = true });
    defer renderer.gc.device.freeMemory(vertex_buffer_memory, null);
    try renderer.gc.device.bindBufferMemory(vertex_buffer, vertex_buffer_memory, 0);

    try renderer.gc.device.beginCommandBuffer(renderer.command_buffer, &.{});

    renderer.gc.device.cmdBeginRenderPass(renderer.command_buffer, &.{
        .render_pass = renderer.render_pass,
        .framebuffer = renderer.framebuffers[renderer.swapchain.image_index],
        .render_area = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = renderer.swapchain.extent,
        },
        .clear_value_count = 1,
        .p_clear_values = @ptrCast(&vk.ClearValue{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } }),
    }, .@"inline");

    renderer.gc.device.cmdBindPipeline(renderer.command_buffer, .graphics, renderer.pipeline);

    const viewport: vk.Viewport = .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(renderer.swapchain.extent.width),
        .height = @floatFromInt(renderer.swapchain.extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor: vk.Rect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = renderer.swapchain.extent,
    };

    renderer.gc.device.cmdSetViewport(renderer.command_buffer, 0, 1, @ptrCast(&viewport));
    renderer.gc.device.cmdSetScissor(renderer.command_buffer, 0, 1, @ptrCast(&scissor));

    var upload_command_buffer: vk.CommandBuffer = undefined;
    try renderer.gc.device.allocateCommandBuffers(&.{
        .command_pool = renderer.command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&upload_command_buffer));
    defer renderer.gc.device.freeCommandBuffers(renderer.command_pool, 1, @ptrCast(&upload_command_buffer));

    var texture_list: std.ArrayList(TextureResources) = .empty;
    defer {
        for (texture_list.items) |texture| {
            texture.deinit(renderer.gc, renderer.descriptor_pool);
        }
        texture_list.deinit(renderer.allocator);
    }

    const vertex_data: [*]Vertex = @ptrCast(@alignCast(try renderer.gc.device.mapMemory(vertex_buffer_memory, 0, vk.WHOLE_SIZE, .{})));
    defer renderer.gc.device.unmapMemory(vertex_buffer_memory);

    var vertex_offset: u32 = 0;

    for (draw_list) |draw_command| {
        const vertices: []const Vertex = switch (draw_command) {
            .simple_rect => |simple_rect| vertices: {
                const color: [3]f32 = .{ @floatFromInt(simple_rect.color.r), @floatFromInt(simple_rect.color.g), @floatFromInt(simple_rect.color.b) };
                break :vertices &.{
                    .{ .pos = .{
                        @as(f32, @floatFromInt(simple_rect.x)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(simple_rect.y)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color, .tex_coord = .{ 0, 0 } },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(simple_rect.x + simple_rect.width)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(simple_rect.y + simple_rect.height)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color, .tex_coord = .{ 1, 1 } },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(simple_rect.x)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(simple_rect.y + simple_rect.height)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color, .tex_coord = .{ 0, 1 } },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(simple_rect.x)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(simple_rect.y)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color, .tex_coord = .{ 0, 0 } },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(simple_rect.x + simple_rect.width)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(simple_rect.y)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color, .tex_coord = .{ 1, 0 } },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(simple_rect.x + simple_rect.width)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(simple_rect.y + simple_rect.height)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color, .tex_coord = .{ 1, 1 } },
                };
            },
            .textured_rect => |textured_rect| vertices: {
                const texture = try createTextureFromData(
                    renderer.gc,
                    upload_command_buffer,
                    renderer.descriptor_pool,
                    renderer.descriptor_set_layout,
                    renderer.sampler,
                    textured_rect.texture_data,
                    @intCast(textured_rect.texture_width),
                    @intCast(textured_rect.texture_height),
                    textured_rect.single_channel,
                );
                try texture_list.append(renderer.allocator, texture);

                const color: [3]f32 = .{ @floatFromInt(textured_rect.color.r), @floatFromInt(textured_rect.color.g), @floatFromInt(textured_rect.color.b) };
                break :vertices &.{
                    .{ .pos = .{
                        @as(f32, @floatFromInt(textured_rect.x)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(textured_rect.y)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color, .tex_coord = .{ 0, 0 } },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(textured_rect.x + textured_rect.width)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(textured_rect.y + textured_rect.height)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color, .tex_coord = .{ 1, 1 } },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(textured_rect.x)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(textured_rect.y + textured_rect.height)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color, .tex_coord = .{ 0, 1 } },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(textured_rect.x)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(textured_rect.y)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color, .tex_coord = .{ 0, 0 } },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(textured_rect.x + textured_rect.width)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(textured_rect.y)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color, .tex_coord = .{ 1, 0 } },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(textured_rect.x + textured_rect.width)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(textured_rect.y + textured_rect.height)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color, .tex_coord = .{ 1, 1 } },
                };
            },
        };

        renderer.gc.device.cmdBindPipeline(renderer.command_buffer, .graphics, renderer.pipeline);
        renderer.gc.device.cmdBindVertexBuffers(renderer.command_buffer, 0, 1, &.{vertex_buffer}, &.{0});

        switch (draw_command) {
            .simple_rect => {
                const push_constants: PushConstants = .{ .use_texture = 0 };
                renderer.gc.device.cmdPushConstants(
                    renderer.command_buffer,
                    renderer.pipeline_layout,
                    .{ .fragment_bit = true },
                    0,
                    @sizeOf(PushConstants),
                    @ptrCast(&push_constants),
                );
            },
            .textured_rect => {
                const push_constants: PushConstants = .{ .use_texture = 1 };
                renderer.gc.device.cmdPushConstants(
                    renderer.command_buffer,
                    renderer.pipeline_layout,
                    .{ .fragment_bit = true },
                    0,
                    @sizeOf(PushConstants),
                    @ptrCast(&push_constants),
                );

                const descriptor_set = texture_list.items[texture_list.items.len - 1].descriptor_set;
                renderer.gc.device.cmdBindDescriptorSets(
                    renderer.command_buffer,
                    .graphics,
                    renderer.pipeline_layout,
                    0,
                    1,
                    @ptrCast(&descriptor_set),
                    0,
                    undefined,
                );
            },
        }

        @memcpy(vertex_data[vertex_offset..][0..vertices.len], vertices);
        renderer.gc.device.cmdDraw(renderer.command_buffer, @intCast(vertices.len), 1, vertex_offset, 0);
        vertex_offset += @intCast(vertices.len);
        std.debug.assert(vertices.len <= vertex_buffer_size_per_command);
    }

    renderer.gc.device.cmdEndRenderPass(renderer.command_buffer);
    try renderer.gc.device.endCommandBuffer(renderer.command_buffer);

    _ = try renderer.swapchain.present(renderer.command_buffer);
}
