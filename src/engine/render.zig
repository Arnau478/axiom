const std = @import("std");
const build_options = @import("build_options");

pub const Backend = enum {
    opengl,
};

pub const Viewport = struct {
    x: usize,
    y: usize,
    width: usize,
    height: usize,
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const Command = union(enum(u8)) {
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

pub fn draw(commands: []const Command, viewport: Viewport, window_width: usize, window_height: usize) void {
    switch (build_options.render_backend) {
        .opengl => @import("render/opengl.zig").draw(commands, viewport, window_width, window_height),
    }
}
