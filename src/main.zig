const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");
const engine = @import("engine");
const glfw = @import("glfw");
const gl = @import("gl");

fn glDebugCallback(_: c_uint, _: c_uint, id: c_uint, severity: c_uint, _: c_int, message: [*:0]const u8, _: ?*const anyopaque) callconv(.C) void {
    const log = std.log.scoped(.opengl);

    switch (severity) {
        gl.DEBUG_SEVERITY_HIGH, gl.DEBUG_SEVERITY_MEDIUM => log.err("{s} (id={d})", .{ message, id }),
        gl.DEBUG_SEVERITY_LOW => log.warn("{s} (id={d})", .{ message, id }),
        gl.DEBUG_SEVERITY_NOTIFICATION => log.info("{s} (id={d})", .{ message, id }),
        else => unreachable,
    }
}

fn glfwErrorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    const log = std.log.scoped(.glfw);

    log.err("{}: {s}", .{ error_code, description });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    glfw.setErrorCallback(glfwErrorCallback);

    if (!glfw.init(.{})) {
        return error.CannotInitGlfw;
    }
    defer glfw.terminate();

    const window = glfw.Window.create(800, 600, "axiom", null, null, .{
        .context_version_major = 3,
        .context_version_minor = 2,
        .opengl_profile = .opengl_core_profile,
        .resizable = true,
    }) orelse return error.CannotCreateWindow;

    defer window.destroy();

    glfw.makeContextCurrent(window);

    var gc: engine.render.GraphicsContext = .{
        .gl_procs = gl_procs: {
            var gl_procs: gl.ProcTable = undefined;
            if (!gl_procs.init(glfw.getProcAddress)) {
                return error.CannotGetGlProc;
            }
            gl.makeProcTableCurrent(&gl_procs);
            break :gl_procs gl_procs;
        },
        .viewport_size = undefined,
    };

    if (builtin.mode == .Debug) {
        gl.Enable(gl.DEBUG_OUTPUT);
        gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS);
        gl.DebugMessageCallback(glDebugCallback, null);
    }

    glfw.swapInterval(1);

    var last_ns = std.time.nanoTimestamp();

    while (!window.shouldClose()) {
        const win_size = window.getSize();
        gc.viewport_size.w = @floatFromInt(win_size.width);
        gc.viewport_size.h = @floatFromInt(win_size.height);
        gl.Viewport(0, 0, @intCast(win_size.width), @intCast(win_size.height));

        // ---
        var tree: engine.FrameTree = .{
            .allocator = allocator,
            .root = .{
                .type = .{
                    .viewport = .{
                        .size = gc.viewport_size,
                    },
                },
            },
        };
        defer tree.deinit();
        _ = try tree.root.appendChild(&tree, .{
            .type = .{
                .box = .{
                    .type = .block,
                    .box_model = .{
                        .position = null,
                        .box_width = null,
                        .box_height = null,
                        .padding = .{ .top = 10, .right = 10, .bottom = 10, .left = 10 },
                        .border = .{ .top = 10, .right = 10, .bottom = 10, .left = 10 },
                        .margin = .{ .top = 10, .right = 10, .bottom = 10, .left = 10 },
                    },
                },
            },
        });
        _ = try tree.root.children.items[0].appendChild(&tree, .{
            .type = .{
                .box = .{
                    .type = .block,
                    .box_model = .{
                        .position = null,
                        .box_width = null,
                        .box_height = null,
                        .padding = .{ .top = 10, .right = 10, .bottom = 10, .left = 10 },
                        .border = .{ .top = 10, .right = 10, .bottom = 10, .left = 10 },
                        .margin = .{ .top = 10, .right = 10, .bottom = 10, .left = 10 },
                    },
                },
            },
        });
        _ = try tree.root.children.items[0].appendChild(&tree, .{
            .type = .{
                .box = .{
                    .type = .block,
                    .box_model = .{
                        .position = null,
                        .box_width = null,
                        .box_height = null,
                        .padding = .{ .top = 10, .right = 10, .bottom = 10, .left = 10 },
                        .border = .{ .top = 10, .right = 10, .bottom = 10, .left = 10 },
                        .margin = .{ .top = 10, .right = 10, .bottom = 10, .left = 10 },
                    },
                },
            },
        });
        // ---

        engine.layout.reflow(&tree);

        gl.ClearColor(0, 0, 0, 1);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        if (builtin.mode == .Debug and options.debug_wireframe) {
            gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE);
        }

        try engine.render.render(&gc, &tree);

        window.swapBuffers();
        glfw.pollEvents();

        const this_ns = std.time.nanoTimestamp();
        defer last_ns = this_ns;
        if (builtin.mode == .Debug and options.debug_log_fps) {
            const dt = @as(f64, @floatFromInt(this_ns - last_ns)) /
                @as(f64, @floatFromInt(std.time.ns_per_s));
            std.log.debug("dt={d: <6.4} fps={d:.2}", .{
                dt,
                1.0 / dt,
            });
        }
    }

    _ = engine;
}
