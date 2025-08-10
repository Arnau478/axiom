const std = @import("std");
const engine = @import("engine");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const renderer = engine.Renderer.init(allocator, .{});
    defer renderer.deinit();

    const surface = try renderer.createSurface(300, 200);
    defer surface.deinit();

    surface.draw(&.{
        .{ .clear = .{ .r = 76, .g = 109, .b = 49 } },
    });

    const pixels = try surface.readPixelsAlloc(allocator, .rgb);
    defer allocator.free(pixels);

    const output = try std.fs.cwd().createFile("output.ppm", .{});
    defer output.close();

    try output.writer().print("P6\n{d} {d}\n255\n", .{ surface.width(), surface.height() });
    try output.writeAll(pixels);
}
