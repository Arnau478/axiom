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

    const attribute_description: [2]vk.VertexInputAttributeDescription = .{
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
    };

    pos: [2]f32,
    color: [3]f32,
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

    const pipeline_layout = try gc.device.createPipelineLayout(&.{}, null);
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
    };
}

pub fn deinit(renderer: Renderer) void {
    renderer.gc.device.destroyCommandPool(renderer.command_pool, null);
    for (renderer.framebuffers) |fb| renderer.gc.device.destroyFramebuffer(fb, null);
    renderer.allocator.free(renderer.framebuffers);
    renderer.gc.device.destroyPipeline(renderer.pipeline, null);
    renderer.gc.device.destroyRenderPass(renderer.render_pass, null);
    renderer.gc.device.destroyPipelineLayout(renderer.pipeline_layout, null);
    renderer.swapchain.deinit(renderer.allocator);
    renderer.gc.deinit();
    renderer.allocator.destroy(renderer.gc);
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
                .blend_enable = .false,
                .src_color_blend_factor = .one,
                .dst_color_blend_factor = .zero,
                .color_blend_op = .add,
                .src_alpha_blend_factor = .one,
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

pub fn drawFrame(renderer: *Renderer, width: usize, height: usize, draw_list: []const engine.paint.Command) !void {
    if (renderer.swapchain.extent.width != width or renderer.swapchain.extent.height != height) {
        try renderer.swapchain.recreate(renderer.allocator, .{ .width = @intCast(width), .height = @intCast(height) });

        for (renderer.framebuffers) |fb| renderer.gc.device.destroyFramebuffer(fb, null);
        renderer.allocator.free(renderer.framebuffers);

        renderer.framebuffers = try createFramebuffers(renderer.gc, renderer.allocator, renderer.render_pass, renderer.swapchain);
    }

    const vertex_buffer_size_per_command = 6;
    const vertex_buffer = try renderer.gc.device.createBuffer(&.{
        .size = @sizeOf(Vertex) * draw_list.len * vertex_buffer_size_per_command, // TODO: Should this be hardcoded?
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
                    }, .color = color },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(simple_rect.x + simple_rect.width)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(simple_rect.y + simple_rect.height)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(simple_rect.x)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(simple_rect.y + simple_rect.height)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(simple_rect.x)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(simple_rect.y)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(simple_rect.x + simple_rect.width)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(simple_rect.y)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color },
                    .{ .pos = .{
                        @as(f32, @floatFromInt(simple_rect.x + simple_rect.width)) / @as(f32, @floatFromInt(width)) * 2 - 1,
                        @as(f32, @floatFromInt(simple_rect.y + simple_rect.height)) / @as(f32, @floatFromInt(height)) * 2 - 1,
                    }, .color = color },
                };
            },
        };

        renderer.gc.device.cmdBindPipeline(renderer.command_buffer, .graphics, renderer.pipeline);
        renderer.gc.device.cmdBindVertexBuffers(renderer.command_buffer, 0, 1, &.{vertex_buffer}, &.{0});

        @memcpy(vertex_data[vertex_offset..][0..vertices.len], vertices);
        renderer.gc.device.cmdDraw(renderer.command_buffer, @intCast(vertices.len), 1, vertex_offset, 0);
        vertex_offset += @intCast(vertices.len);
        std.debug.assert(vertices.len <= vertex_buffer_size_per_command);
    }

    renderer.gc.device.cmdEndRenderPass(renderer.command_buffer);
    try renderer.gc.device.endCommandBuffer(renderer.command_buffer);

    _ = try renderer.swapchain.present(renderer.command_buffer);
}
