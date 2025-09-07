const Renderer = @This();

const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan.zig");
const GraphicsContext = @import("GraphicsContext.zig");
const Swapchain = @import("Swapchain.zig");

const vert_spv align(4) = @embedFile("vert_spv").*;
const frag_spv align(4) = @embedFile("frag_spv").*;

allocator: std.mem.Allocator,
gc: *GraphicsContext,
swapchain: Swapchain,
pipeline_layout: vk.PipelineLayout,

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

    try createPipeline(gc);

    return .{
        .allocator = options.allocator,
        .gc = gc,
        .swapchain = swapchain,
        .pipeline_layout = pipeline_layout,
    };
}

fn createShaderModule(gc: *const GraphicsContext, spv: []align(4) const u8) !vk.ShaderModule {
    return try gc.device.createShaderModule(&.{
        .code_size = spv.len,
        .p_code = @ptrCast(spv.ptr),
    }, null);
}

fn createPipeline(gc: *const GraphicsContext) !void {
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
        .vertex_binding_description_count = 0,
        .vertex_attribute_description_count = 0,
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

    _ = shader_stages_info;
    _ = dynamic_info;
    _ = vertex_input_info;
    _ = input_assembly_info;
    _ = viewport_info;
    _ = rasterizer_info;
    _ = multisampling_info;
    _ = color_blend_info;
}

pub fn deinit(renderer: Renderer) void {
    renderer.gc.device.destroyPipelineLayout(renderer.pipeline_layout, null);
    renderer.swapchain.deinit(renderer.allocator);
    renderer.gc.deinit();
    renderer.allocator.destroy(renderer.gc);
}
