const SoftwareRenderer = @This();

const std = @import("std");
const Renderer = @import("../Renderer.zig");

allocator: std.mem.Allocator,

pub const InitOptions = struct {};

pub fn init(allocator: std.mem.Allocator, _: InitOptions) SoftwareRenderer {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(_: SoftwareRenderer) void {}

pub const Surface = struct {
    width: usize,
    height: usize,
    format: Renderer.PixelFormat,
    buffer: [*]u8,

    fn bufferSlice(surface: Surface) []u8 {
        return surface.buffer[0 .. surface.width * surface.height * surface.format.depth()];
    }
};

pub fn createSurface(renderer: SoftwareRenderer, width: usize, height: usize) !Surface {
    const format: Renderer.PixelFormat = .argb;

    return .{
        .width = width,
        .height = height,
        .format = format,
        .buffer = (try renderer.allocator.alloc(u8, width * height * format.depth())).ptr,
    };
}

pub fn destroySurface(renderer: SoftwareRenderer, surface: Surface) void {
    renderer.allocator.free(surface.bufferSlice());
}

pub fn getSurfaceWidth(_: SoftwareRenderer, surface: Surface) usize {
    return surface.width;
}

pub fn getSurfaceHeight(_: SoftwareRenderer, surface: Surface) usize {
    return surface.height;
}

pub fn readSurfacePixels(_: SoftwareRenderer, surface: Surface, buffer: []u8, format: Renderer.PixelFormat) !void {
    for (0..surface.width * surface.height) |i| {
        const color = surface.format.decodeColor(surface.bufferSlice()[i * surface.format.depth() ..][0..surface.format.depth()]);
        format.encodeColor(color, buffer[i * format.depth() ..][0..format.depth()]);
    }
}

pub fn doCommand(_: SoftwareRenderer, surface: Surface, command: Renderer.Command) void {
    switch (command) {
        .clear => |color| {
            for (0..surface.width * surface.height) |i| {
                surface.format.encodeColor(color, surface.bufferSlice()[i * surface.format.depth() ..][0..surface.format.depth()]);
            }
        },
    }
}
