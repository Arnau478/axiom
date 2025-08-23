const Renderer = @This();

const std = @import("std");
const build_options = @import("build_options");

pub const Backend = @import("Renderer/backend.zig").Backend;

const Impl = switch (build_options.renderer_backend) {
    .software => @import("Renderer/SoftwareRenderer.zig"),
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const PixelFormat = enum {
    rgb,
    argb,

    pub fn depth(format: PixelFormat) usize {
        return switch (format) {
            .rgb => 3,
            .argb => 4,
        };
    }

    pub fn encodeColor(format: PixelFormat, color: Renderer.Color, buffer: []u8) void {
        std.debug.assert(buffer.len == format.depth());
        @memcpy(buffer, @as([]const u8, switch (format) {
            .rgb => &.{ color.r, color.g, color.b },
            .argb => &.{ 0, color.r, color.g, color.b },
        }));
    }

    pub fn decodeColor(format: PixelFormat, encoded: []const u8) Renderer.Color {
        std.debug.assert(encoded.len == format.depth());
        return switch (format) {
            .rgb => .{ .r = encoded[0], .g = encoded[1], .b = encoded[2] },
            .argb => .{ .r = encoded[1], .g = encoded[2], .b = encoded[3] },
        };
    }
};

pub const Command = union(enum) {
    clear: Color,
    simple_rect: SimpleRect,

    pub const SimpleRect = struct {
        x: usize,
        y: usize,
        width: usize,
        height: usize,
        color: Color,
    };
};

impl: Impl,

pub fn init(allocator: std.mem.Allocator, options: Impl.InitOptions) Renderer {
    return .{
        .impl = Impl.init(allocator, options),
    };
}

pub fn deinit(renderer: Renderer) void {
    renderer.impl.deinit();
}

pub const Surface = struct {
    renderer: *const Renderer,
    impl: Impl.Surface,

    pub fn draw(surface: Surface, commands: []const Command) void {
        for (commands) |command| {
            surface.renderer.impl.doCommand(surface.impl, command);
        }
    }

    pub fn deinit(surface: Surface) void {
        surface.renderer.impl.destroySurface(surface.impl);
    }

    pub fn width(surface: Surface) usize {
        return surface.renderer.impl.getSurfaceWidth(surface.impl);
    }

    pub fn height(surface: Surface) usize {
        return surface.renderer.impl.getSurfaceHeight(surface.impl);
    }

    pub fn readPixels(surface: Surface, buffer: []u8, format: PixelFormat) void {
        std.debug.assert(buffer.len == surface.width() * surface.height() * format.depth());
        try surface.renderer.impl.readSurfacePixels(surface.impl, buffer, format);
    }

    pub fn readPixelsAlloc(surface: Surface, allocator: std.mem.Allocator, format: PixelFormat) ![]u8 {
        const buffer = try allocator.alloc(u8, surface.width() * surface.height() * format.depth());
        errdefer allocator.free(buffer);
        surface.readPixels(buffer, format);
        return buffer;
    }
};

pub fn createSurface(renderer: *const Renderer, width: usize, height: usize) !Surface {
    return .{
        .renderer = renderer,
        .impl = try renderer.impl.createSurface(width, height),
    };
}
