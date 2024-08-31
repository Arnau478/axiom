const std = @import("std");
const gl = @import("gl");
const engine = @import("engine.zig");

pub const GraphicsContext = @import("render/GraphicsContext.zig");
pub const Color = @import("render/Color.zig");

const log = std.log.scoped(.@"axiom/render");

pub fn render(gc: *const GraphicsContext, tree: *const engine.FrameTree) !void {
    gl.makeProcTableCurrent(&gc.gl_procs);

    gl.Enable(gl.DEPTH_TEST);
    gl.DepthFunc(gl.LEQUAL);

    gl.Enable(gl.CULL_FACE);

    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    const vert = gl.CreateShader(gl.VERTEX_SHADER);
    gl.ShaderSource(vert, 1, @ptrCast(&@embedFile("render/shaders/base.vert")), null);
    gl.CompileShader(vert);
    defer gl.DeleteShader(vert);

    const frag = gl.CreateShader(gl.FRAGMENT_SHADER);
    gl.ShaderSource(frag, 1, @ptrCast(&@embedFile("render/shaders/base.frag")), null);
    gl.CompileShader(frag);
    defer gl.DeleteShader(frag);

    const program = gl.CreateProgram();
    gl.AttachShader(program, vert);
    gl.AttachShader(program, frag);
    gl.LinkProgram(program);

    gl.UseProgram(program);

    renderNode(gc, tree.root);
}

fn renderNode(gc: *const GraphicsContext, node: engine.FrameTree.Node) void {
    switch (node.type) {
        .viewport => {},
        .box => |box| {
            drawRect(gc, box.box_model.marginRect().?, Color.comptimeHex("#C04000"));
            drawRect(gc, box.box_model.borderRect().?, Color.comptimeHex("#808080"));
            drawRect(gc, box.box_model.paddingRect().?, Color.comptimeHex("#800080"));
            drawRect(gc, box.box_model.contentRect().?, Color.comptimeHex("#008080"));
        },
    }

    var children_iter = std.mem.reverseIterator(node.children.items);
    while (children_iter.next()) |child| {
        renderNode(gc, child);
    }
}

fn drawRect(gc: *const GraphicsContext, rect: engine.Rect, color: Color) void {
    const vertices: [4 * 6]f32 =
        pointToNdc(gc, rect.cornerPos(.bottom_left)) ++ color.toFloats() ++
        pointToNdc(gc, rect.cornerPos(.bottom_right)) ++ color.toFloats() ++
        pointToNdc(gc, rect.cornerPos(.top_left)) ++ color.toFloats() ++
        pointToNdc(gc, rect.cornerPos(.top_right)) ++ color.toFloats();

    var vao: c_uint = undefined;
    gl.CreateVertexArrays(1, (&vao)[0..1]);
    defer gl.DeleteVertexArrays(1, (&vao)[0..1]);
    gl.BindVertexArray(vao);

    var vbo: c_uint = undefined;
    gl.CreateBuffers(1, (&vbo)[0..1]);
    defer gl.DeleteBuffers(1, (&vbo)[0..1]);
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(f32) * vertices.len, &vertices, gl.STATIC_DRAW);

    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(f32) * 6, 0);
    gl.EnableVertexAttribArray(0);
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, @sizeOf(f32) * 6, @sizeOf(f32) * 3);
    gl.EnableVertexAttribArray(1);

    gl.DrawArrays(gl.TRIANGLE_STRIP, 0, @divExact(vertices.len, 6));
}

fn pointToNdc(gc: *const GraphicsContext, pos: @Vector(2, f64)) [3]f32 {
    var res: @Vector(2, f32) = @floatCast(pos);

    res *= @splat(2);

    res[0] /= @floatCast(gc.viewport_size.w);
    res[1] /= @floatCast(gc.viewport_size.h);

    res -= [_]f32{ 1, 1 };

    res[1] *= -1;

    return [3]f32{
        res[0],
        res[1],
        0,
    };
}
