const std = @import("std");

pub fn build(b: *std.Build) void {
    const html = b.addModule("html", .{
        .root_source_file = b.path("src/html.zig"),
    });

    const test_html = b.addTest(.{
        .root_source_file = b.path("src/html.zig"),
    });

    const test_html_step = b.step("test-html", "Test the html module");
    test_html_step.dependOn(&b.addRunArtifact(test_html).step);

    _ = html;
}
