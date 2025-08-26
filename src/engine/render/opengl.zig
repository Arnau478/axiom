const std = @import("std");
const build_options = @import("build_options");
const gl = @import("gl");
const render = @import("../render.zig");

pub fn draw(commands: []const render.Command, viewport_width: f32, viewport_height: f32) void {
    if (build_options.render_wireframe_mode) {
        gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE);
    } else {
        gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL);
    }

    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

    gl.Disable(gl.DEPTH_TEST);
    gl.Disable(gl.CULL_FACE);
    gl.Viewport(0, 0, @intFromFloat(viewport_width), @intFromFloat(viewport_height));

    // TODO: Avoid recompiling shaders

    const vert_shader = gl.CreateShader(gl.VERTEX_SHADER);
    gl.ShaderSource(vert_shader, 1, &.{@embedFile("opengl/shader.vert")}, null);
    gl.CompileShader(vert_shader);
    defer gl.DeleteShader(vert_shader);

    const frag_shader = gl.CreateShader(gl.FRAGMENT_SHADER);
    gl.ShaderSource(frag_shader, 1, &.{@embedFile("opengl/shader.frag")}, null);
    gl.CompileShader(frag_shader);
    defer gl.DeleteShader(frag_shader);

    const program = gl.CreateProgram();
    gl.AttachShader(program, vert_shader);
    gl.AttachShader(program, frag_shader);
    gl.LinkProgram(program);
    gl.UseProgram(program);

    for (commands) |command| {
        switch (command) {
            .clear => |color| {
                gl.ClearColor(
                    @as(f32, @floatFromInt(color.r)) / 255.0,
                    @as(f32, @floatFromInt(color.g)) / 255.0,
                    @as(f32, @floatFromInt(color.b)) / 255.0,
                    1.0,
                );
                gl.Clear(gl.COLOR);
            },
            .simple_rect => |simple_rect| {
                const x1 = (@as(f32, @floatFromInt(simple_rect.x)) / viewport_width) * 2 - 1;
                const x2 = (@as(f32, @floatFromInt(simple_rect.x + simple_rect.width)) / viewport_width) * 2 - 1;
                const y1 = 1 - (@as(f32, @floatFromInt(simple_rect.y)) / viewport_height) * 2;
                const y2 = 1 - (@as(f32, @floatFromInt(simple_rect.y + simple_rect.height)) / viewport_height) * 2;

                const r = @as(f32, @floatFromInt(simple_rect.color.r)) / 255.0;
                const g = @as(f32, @floatFromInt(simple_rect.color.g)) / 255.0;
                const b = @as(f32, @floatFromInt(simple_rect.color.b)) / 255.0;

                const vertices = [_]f32{
                    x1, y1, r, g, b,
                    x2, y1, r, g, b,
                    x1, y2, r, g, b,
                    x2, y1, r, g, b,
                    x2, y2, r, g, b,
                    x1, y2, r, g, b,
                };

                var vao: c_uint = undefined;
                gl.GenVertexArrays(1, (&vao)[0..1]);
                defer gl.DeleteVertexArrays(1, (&vao)[0..1]);
                gl.BindVertexArray(vao);

                var vbo: c_uint = undefined;
                gl.GenBuffers(1, (&vbo)[0..1]);
                defer gl.DeleteBuffers(1, (&vbo)[0..1]);
                gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
                gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(f32) * vertices.len, &vertices, gl.STATIC_DRAW);

                gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 5 * @sizeOf(f32), 0);
                gl.EnableVertexAttribArray(0);
                gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 5 * @sizeOf(f32), 2 * @sizeOf(f32));
                gl.EnableVertexAttribArray(1);

                gl.DrawArrays(gl.TRIANGLES, 0, 6);
            },
        }
    }
}
