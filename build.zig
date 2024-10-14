const std = @import("std");
const rlz = @import("raylib-zig");

pub fn build(b: *std.Build) !void {
    // std.debug.print("SYSROOT: {s}", .{b.sysroot.?});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // raylib_artifact.defineCMacro("SUPPORT_FILEFORMAT_JPG", null);
    if (target.query.os_tag == .emscripten) {
        const exe_lib = b.addStaticLibrary(.{
            .name = "zorsh",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe_lib.root_module.addAnonymousImport("map", .{ .root_source_file = b.path("assets/map") });

        const emsdk = b.dependency("emsdk", .{});
        const path = emsdk.path(b.pathJoin(&.{ "upstream", "emscripten" })).getPath(b);
        b.sysroot = try std.fs.path.relative(std.heap.page_allocator, b.path("").getPath(b), path);
        const raylib_dep = b.dependency("raylib-zig", .{
            .target = target,
            .optimize = optimize,
            .linux_display_backend = .Wayland,
            .opengl_version = rlz.OpenglVersion.gles_3,
        });
        const raylib_artifact = raylib_dep.artifact("raylib");
        raylib_artifact.addIncludePath(emsdk.path(b.pathJoin(&.{
            "upstream",
            "emscripten",
            "cache",
            "sysroot",
            "include",
        })));
        exe_lib.linkLibrary(raylib_artifact);
        exe_lib.root_module.addImport("raylib", raylib_dep.module("raylib"));
        exe_lib.root_module.addImport("raygui", raylib_dep.module("raygui"));

        const mkdir_cmd = b.addSystemCommand(&[_][]const u8{ "mkdir", "-p", "www" });
        const emcc = b.addSystemCommand(&.{
            emsdk.path(b.pathJoin(&.{ "upstream", "emscripten", "emcc" })).getPath(b),
        });
        // emcc.setName("emcc");
        emcc.step.dependOn(&mkdir_cmd.step);
        emcc.addFileArg(exe_lib.getEmittedBin());
        emcc.step.dependOn(&exe_lib.step);
        emcc.addFileArg(raylib_artifact.getEmittedBin());
        emcc.step.dependOn(&raylib_artifact.step);
        emcc.addArgs(&[_][]const u8{
            "-sFULL_ES3",
            "-sUSE_GLFW=3",
            "-sASYNCIFY",
            // "--emrun",
            "-O3",
            // "-flto",
            // "--closure",
            // "1",
            // "-sUSE_WEBGPU",
            "-sUSE_OFFSET_CONVERTER",
            "-sEXIT_RUNTIME",
            "-sALLOW_MEMORY_GROWTH",
            // "-sMALLOC='emmalloc'",
            // "-sSTACK_SIZE=256MB",
            // "-sTOTAL_MEMORY=512MB",
            "--preload-file",
            "assets",
            "-owww/index.html",
            //Debug
            // "-Og",
            // "-sSAFE_HEAP=1",
            // "-sSTACK_OVERFLOW_CHECK=1",
            // "-sASSERTIONS",
        });

        b.getInstallStep().dependOn(&emcc.step);
        const run_step = try rlz.emcc.emscriptenRunStep(b);
        run_step.step.dependOn(&emcc.step);
        const run_option = b.step("run", "Run zorsh");
        run_option.dependOn(&run_step.step);
    } else {
        const raylib_dep = b.dependency("raylib-zig", .{
            .target = target,
            .optimize = optimize,
            .linux_display_backend = .Wayland,
            // .opengl_version = rlz.OpenglVersion.gles_3, //
        });

        const raylib_artifact = raylib_dep.artifact("raylib"); // C library
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
