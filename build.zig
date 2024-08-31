const std = @import("std");
const zigglgen = @import("zigglgen");

pub fn build(b: *std.Build) void {
    const gl_bindings = zigglgen.generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.6",
        .profile = .core,
    });

    const engine = b.addModule("engine", .{
        .root_source_file = b.path("src/engine/engine.zig"),
    });

    engine.addImport("gl", gl_bindings);

    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    if (optimize == .Debug) {
        const debug_options = [_]std.meta.Tuple(&.{ type, []const u8, []const u8, bool }){
            .{ bool, "wireframe", "Display triangles in wireframe mode", false },
            .{ bool, "log_fps", "Log the FPS count", false },
        };

        inline for (debug_options) |option| {
            options.addOption(option[0], "debug_" ++ option[1], b.option(option[0], "debug_" ++ option[1], option[2]) orelse option[3]);
        }
    }

    const exe = b.addExecutable(.{
        .name = "axiom",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addOptions("options", options);

    exe.root_module.addImport("engine", engine);
    exe.root_module.addImport("gl", gl_bindings);
    exe.root_module.addImport("glfw", b.dependency("zig_glfw", .{
        .target = target,
        .optimize = optimize,
    }).module("zig-glfw"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the web browser");
    run_step.dependOn(&run_cmd.step);
}
