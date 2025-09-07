const vk = @import("vk");

pub const Swapchain = @import("Swapchain.zig");
pub const GraphicsContext = @import("GraphicsContext.zig");
pub const Renderer = @import("Renderer.zig");

pub const GetInstanceProcAddressFunction = fn (instance: vk.Instance, procname: [*:0]const u8) callconv(.c) vk.PfnVoidFunction;
pub const CreateWindowSurfaceFunction = fn (instance: vk.Instance, ctx: *anyopaque, allocator: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) callconv(.c) vk.Result;
