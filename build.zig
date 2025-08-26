const std = @import("std");
const render = @import("src/engine/render.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const render_backend = b.option(render.Backend, "render_backend", "The render backend to use") orelse .opengl;

    const render_wireframe_mode = b.option(bool, "render_wireframe_mode", "The render backend to use") orelse false;

    const paint_box_model = b.option(bool, "paint_box_model", "Paint the CSS box model for debugging purposes") orelse false;

    const zglfw_dep = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
    });

    const engine_build_options = b.addOptions();
    engine_build_options.addOption(render.Backend, "render_backend", render_backend);
    engine_build_options.addOption(bool, "render_wireframe_mode", render_wireframe_mode);
    engine_build_options.addOption(bool, "paint_box_model", paint_box_model);

    const engine_mod = b.createModule(.{
        .root_source_file = b.path("src/engine/engine.zig"),
        .target = target,
        .optimize = optimize,
    });

    engine_mod.addOptions("build_options", engine_build_options);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("glfw", zglfw_dep.module("root"));
    if (target.result.os.tag != .emscripten) {
        exe_mod.linkLibrary(zglfw_dep.artifact("glfw"));
    }

    exe_mod.addImport("engine", engine_mod);

    switch (render_backend) {
        .opengl => {
            const gl = @import("zigglgen").generateBindingsModule(b, .{
                .api = .gl,
                .version = .@"4.3",
                .profile = .core,
                .extensions = &.{},
            });

            engine_mod.addImport("gl", gl);
            exe_mod.addImport("gl", gl);
        },
    }

    const exe = b.addExecutable(.{
        .name = "axiom",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const engine_unit_tests = b.addTest(.{
        .root_module = engine_mod,
    });

    const run_engine_unit_tests = b.addRunArtifact(engine_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_engine_unit_tests.step);
}
