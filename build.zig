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

    const css = b.addModule("css", .{
        .root_source_file = b.path("src/css.zig"),
    });

    const test_css = b.addTest(.{
        .root_source_file = b.path("src/css.zig"),
    });

    const test_css_step = b.step("test-css", "Test the css module");
    test_css_step.dependOn(&b.addRunArtifact(test_css).step);

    _ = html;
    _ = css;
}
