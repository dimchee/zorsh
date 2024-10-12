const std = @import("std");
const rlz = @import("raylib-zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const raylib_dep = b.dependency("raylib-zig", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .Wayland,
        .opengl_version = rlz.OpenglVersion.gl_2_1, // Use OpenGL 2.1 (requires importing raylib-zig's build script)
    });

    const raylib_artifact = raylib_dep.artifact("raylib"); // C library
    raylib_artifact.defineCMacro("SUPPORT_FILEFORMAT_JPG", null);
    if (target.query.os_tag == .emscripten) {
        const exe_lib = rlz.emcc.compileForEmscripten(b, "zorsh", "src/main.zig", target, optimize);
        exe_lib.root_module.addAnonymousImport("map", .{
            .root_source_file = b.path("assets/map"),
        });
        const include = .{ .cwd_relative = b.pathJoin(&.{ b.sysroot.?, "cache", "sysroot", "include" }) };
        raylib_artifact.addIncludePath(include);
        exe_lib.addIncludePath(include);
        exe_lib.entry = .disabled;

        const raylib_module = raylib_dep.module("raylib");
        raylib_module.addIncludePath(include);
        exe_lib.linkLibrary(raylib_artifact);
        exe_lib.root_module.addImport("raylib", raylib_module);
        exe_lib.root_module.addImport("raygui", raylib_dep.module("raygui"));

        // Note that raylib itself is not actually added to the exe_lib output file, so it also needs to be linked with emscripten.
        const link_step = try rlz.emcc.linkWithEmscripten(b, &[_]*std.Build.Step.Compile{ exe_lib, raylib_artifact });
        //this lets your program access files like "resources/my-image.png":
        link_step.addArg("--embed-file");
        link_step.addArg("assets/");

        b.getInstallStep().dependOn(&link_step.step);
        const run_step = try rlz.emcc.emscriptenRunStep(b);
        run_step.step.dependOn(&link_step.step);
        const run_option = b.step("run", "Run zorsh");
        run_option.dependOn(&run_step.step);
    } else {
        const exe = b.addExecutable(.{
            .name = "zorsh",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addAnonymousImport("map", .{
            .root_source_file = b.path("assets/map"),
        });
        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        run_cmd.addArgs(b.args orelse &.{});

        const unit_tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        b.step("run", "Run the app").dependOn(&run_cmd.step);
        b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(unit_tests).step);
        exe.linkLibrary(raylib_artifact);
        exe.root_module.addImport("raylib", raylib_dep.module("raylib"));
        exe.root_module.addImport("raygui", raylib_dep.module("raygui"));
    }
}
