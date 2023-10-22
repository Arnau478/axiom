const std = @import("std");
const ui = @import("../../ui.zig");
const Stylesheet = @import("../../Stylesheet.zig");
const Rect = @import("../../Rect.zig");

const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
});

var display: *c.Display = undefined;
var screen: c_int = undefined;
var window: c.Window = undefined;

pub fn init() !void {
    display = c.XOpenDisplay(null) orelse return error.CannotOpenDisplay;

    screen = c.DefaultScreen(display);

    window = c.XCreateSimpleWindow(display, c.RootWindow(display, screen), 10, 10, 100, 100, 1, c.BlackPixel(display, screen), c.WhitePixel(display, screen));

    _ = c.XSelectInput(display, window, c.ExposureMask | c.KeyPressMask);
    _ = c.XMapWindow(display, window);
}

pub fn deinit() void {
    _ = c.XCloseDisplay(display);
}

pub fn getEvent() ui.Event {
    var event: c.XEvent = undefined;
    _ = c.XNextEvent(display, &event);

    return switch (event.type) {
        c.Expose => .{
            .expose = .{
                .width = @intCast(event.xexpose.width),
                .height = @intCast(event.xexpose.height),
            },
        },
        c.KeyPress => .{
            .key_press = .{
                .key = parseXkey(c.XLookupKeysym(&event.xkey, 0)),
            },
        },
        else => @panic("Unimplemented xlib event"),
    };
}

pub fn drawRectangle(rect: Rect, color: Stylesheet.Value.Color, fill: bool) void {
    _ = c.XSetForeground(display, c.DefaultGC(display, screen), xlibColor(color));
    if (fill) {
        _ = c.XFillRectangle(display, window, c.DefaultGC(display, screen), @intFromFloat(rect.x), @intFromFloat(rect.y), @intFromFloat(rect.w), @intFromFloat(rect.h));
    } else {
        _ = c.XDrawRectangle(display, window, c.DefaultGC(display, screen), @intFromFloat(rect.x), @intFromFloat(rect.y), @intFromFloat(rect.w), @intFromFloat(rect.h));
    }
}

inline fn xlibColor(color: Stylesheet.Value.Color) c_ulong {
    return @as(c_ulong, color.b) + (@as(c_ulong, color.g) << 8) + (@as(c_ulong, color.r) << 16);
}

inline fn parseXkey(xkey: c_ulong) ui.Key {
    return switch (xkey) {
        c.XK_Escape => .escape,
        c.XK_Shift_L, c.XK_Shift_R => .shift,
        c.XK_space => .space,
        c.XK_BackSpace => .backspace,
        c.XK_a, c.XK_A => .a,
        c.XK_b, c.XK_B => .b,
        c.XK_c, c.XK_C => .c,
        c.XK_d, c.XK_D => .d,
        c.XK_e, c.XK_E => .e,
        c.XK_f, c.XK_F => .f,
        c.XK_g, c.XK_G => .g,
        c.XK_h, c.XK_H => .h,
        c.XK_i, c.XK_I => .i,
        c.XK_j, c.XK_J => .j,
        c.XK_k, c.XK_K => .k,
        c.XK_l, c.XK_L => .l,
        c.XK_m, c.XK_M => .m,
        c.XK_n, c.XK_N => .n,
        c.XK_o, c.XK_O => .o,
        c.XK_p, c.XK_P => .p,
        c.XK_q, c.XK_Q => .q,
        c.XK_r, c.XK_R => .r,
        c.XK_s, c.XK_S => .s,
        c.XK_t, c.XK_T => .t,
        c.XK_u, c.XK_U => .u,
        c.XK_v, c.XK_V => .v,
        c.XK_w, c.XK_W => .w,
        c.XK_x, c.XK_X => .x,
        c.XK_y, c.XK_Y => .y,
        c.XK_z, c.XK_Z => .z,
        else => blk: {
            std.debug.print("Unimplemented XKey {d}\n", .{xkey});
            break :blk .escape;
        },
    };
}
