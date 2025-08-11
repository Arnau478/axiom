const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const renderer_backend = b.option(@import("src/engine/Renderer/backend.zig").Backend, "renderer_backend", "The renderer backend to use") orelse .software;

    const engine_build_options = b.addOptions();
    engine_build_options.addOption(@TypeOf(renderer_backend), "renderer_backend", renderer_backend);

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

    exe_mod.addImport("engine", engine_mod);

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
