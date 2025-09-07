const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const vulkan_override_registry = b.option([]const u8, "vulkan_override_registry", "Override the path to the Vulkan registry");
    const paint_box_model = b.option(bool, "paint_box_model", "Paint the CSS box model for debugging purposes") orelse false;

    const zglfw_dep = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
    });

    const freefont_dep = b.dependency("freefont", .{});

    const vulkan_registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    const vulkan_registry_path: std.Build.LazyPath = if (vulkan_override_registry) |override_registry|
        .{ .cwd_relative = override_registry }
    else
        vulkan_registry;

    const vulkan_dep = b.dependency("vulkan_zig", .{
        .registry = vulkan_registry_path,
    });

    const engine_build_options = b.addOptions();
    engine_build_options.addOption(bool, "paint_box_model", paint_box_model);

    const engine_mod = b.addModule("engine", .{
        .root_source_file = b.path("src/engine/engine.zig"),
        .target = target,
        .optimize = optimize,
    });

    engine_mod.addOptions("build_options", engine_build_options);

    const vulkan_mod = b.addModule("vulkan", .{
        .root_source_file = b.path("src/vulkan/vulkan.zig"),
        .target = target,
        .optimize = optimize,
    });

    vulkan_mod.addImport("vk", vulkan_dep.module("vulkan-zig"));

    const vert_cmd = b.addSystemCommand(&.{ "glslc", "--target-env=vulkan1.2", "-o" });
    const vert_spv = vert_cmd.addOutputFileArg("vert.spv");
    vert_cmd.addFileArg(b.path("src/vulkan/shaders/shader.vert"));
    vulkan_mod.addAnonymousImport("vert_spv", .{ .root_source_file = vert_spv });

    const frag_cmd = b.addSystemCommand(&.{ "glslc", "--target-env=vulkan1.2", "-o" });
    const frag_spv = frag_cmd.addOutputFileArg("frag.spv");
    frag_cmd.addFileArg(b.path("src/vulkan/shaders/shader.frag"));
    vulkan_mod.addAnonymousImport("frag_spv", .{ .root_source_file = frag_spv });

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
    exe_mod.addImport("vulkan", vulkan_mod);

    exe_mod.addAnonymousImport("default_font", .{ .root_source_file = freefont_dep.path("ttf/FreeSans.ttf") });

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
