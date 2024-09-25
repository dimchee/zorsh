const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
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

    const raylib_dep = b.dependency("raylib-zig", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .Wayland,
    });

    const raylib_artifact = raylib_dep.artifact("raylib"); // C library
    raylib_artifact.defineCMacro("SUPPORT_FILEFORMAT_JPG", null);
    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib_dep.module("raylib"));
    exe.root_module.addImport("raygui", raylib_dep.module("raygui"));
}
