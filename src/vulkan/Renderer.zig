const Renderer = @This();

const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan.zig");

const log = std.log.scoped(.vulkan);

fn debugUtilsMessengerCallback(
    severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    msg_type: vk.DebugUtilsMessageTypeFlagsEXT,
    callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(.c) vk.Bool32 {
    const severity_str = if (severity.verbose_bit_ext)
        "verbose"
    else if (severity.info_bit_ext)
        "info"
    else if (severity.warning_bit_ext)
        "warning"
    else if (severity.error_bit_ext)
        "error"
    else
        "unknown";

    const type_str = if (msg_type.general_bit_ext)
        "general"
    else if (msg_type.validation_bit_ext)
        "validation"
    else if (msg_type.performance_bit_ext)
        "performance"
    else if (msg_type.device_address_binding_bit_ext)
        "device addr"
    else
        "unknown";

    const message: [*c]const u8 = if (callback_data) |data| data.p_message else "(no message)";

    // TODO: use different log levels depending on severity
    log.debug("Vulkan debug messenger (severity=\"{s}\", type=\"{s}\"): {s}", .{ severity_str, type_str, message });

    return .false;
}

const PickedDevice = struct {
    physical_device: vk.PhysicalDevice,
    properties: vk.PhysicalDeviceProperties,
};

fn pickPhyisicalDevice(allocator: std.mem.Allocator, instance: vk.InstanceProxy, surface: vk.SurfaceKHR) !PickedDevice {
    _ = surface;

    const devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(devices);

    var best_device: ?PickedDevice = null;
    var best_device_score: usize = 0;

    for (devices, 0..) |device, i| {
        const device_properties = instance.getPhysicalDeviceProperties(device);

        var score: usize = 0;

        score += device_properties.limits.max_image_dimension_2d;
        if (device_properties.device_type == .discrete_gpu) score += 1000;

        std.log.debug("PhysicalDevice {d}: \"{s}\" [{s}] (score={d})", .{ i, device_properties.device_name, if (score > 0) "suitable" else "not suitable", score });

        if (best_device_score < score) {
            best_device = .{
                .physical_device = device,
                .properties = device_properties,
            };
            best_device_score = score;
        }
    }

    if (best_device) |dev| return dev else return error.NoSuitablePhysicalDevice;
}

allocator: std.mem.Allocator,
vkb: vk.BaseWrapper,
instance: vk.InstanceProxy,
debug_messenger: vk.DebugUtilsMessengerEXT,
surface: vk.SurfaceKHR,

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
    loader: *const vulkan.GetInstanceProcAddressFunction,
    extensions: []const [*:0]const u8,
    application_name: [*:0]const u8,
    createWindowSurface: *const vulkan.CreateWindowSurfaceFunction,
    create_window_surface_ctx: *anyopaque,
};

pub fn init(options: InitOptions) !Renderer {
    var extensions: std.ArrayList([*:0]const u8) = .empty;
    defer extensions.deinit(options.allocator);

    try extensions.append(options.allocator, vk.extensions.ext_debug_utils.name);
    try extensions.append(options.allocator, vk.extensions.khr_portability_enumeration.name);
    try extensions.append(options.allocator, vk.extensions.khr_get_physical_device_properties_2.name);

    try extensions.appendSlice(options.allocator, options.extensions);

    const vkb = vk.BaseWrapper.load(options.loader);
    const instance_handle = try vkb.createInstance(&.{
        .flags = .{ .enumerate_portability_bit_khr = true },
        .p_application_info = &.{
            .p_application_name = options.application_name,
            .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
            .p_engine_name = "axiom",
            .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
            .api_version = @bitCast(vk.API_VERSION_1_2),
        },
        .enabled_extension_count = @intCast(extensions.items.len),
        .pp_enabled_extension_names = extensions.items.ptr,
    }, null);

    const vki = try options.allocator.create(vk.InstanceWrapper);
    errdefer options.allocator.destroy(vki);
    vki.* = vk.InstanceWrapper.load(instance_handle, vkb.dispatch.vkGetInstanceProcAddr.?);
    const instance = vk.InstanceProxy.init(instance_handle, vki);
    errdefer instance.destroyInstance(null);

    const debug_messenger = try instance.createDebugUtilsMessengerEXT(&.{
        .message_severity = .{
            .warning_bit_ext = true,
            .error_bit_ext = true,
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = &debugUtilsMessengerCallback,
        .p_user_data = null,
    }, null);
    errdefer instance.destroyDebugUtilsMessengerEXT(debug_messenger, null);

    const surface = surface: {
        var surface: vk.SurfaceKHR = undefined;
        if (options.createWindowSurface(instance.handle, options.create_window_surface_ctx, null, &surface) != .success) return error.SurfaceCreationFailed;
        break :surface surface;
    };
    errdefer instance.destroySurfaceKHR(surface, null);

    const physical_device = try pickPhyisicalDevice(options.allocator, instance, surface);
    _ = physical_device;

    return .{
        .allocator = options.allocator,
        .vkb = vkb,
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
    };
}

pub fn deinit(renderer: *Renderer) void {
    renderer.instance.destroySurfaceKHR(renderer.surface, null);
    renderer.instance.destroyDebugUtilsMessengerEXT(renderer.debug_messenger, null);
    renderer.instance.destroyInstance(null);

    renderer.allocator.destroy(renderer.instance.wrapper);
}
