const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const frameworkRoot = std.Build.LazyPath{
        .cwd_relative = "/opt/homebrew/Cellar/python@3.13/3.13.1/Frameworks/Python.framework/Versions/3.13/",
    };
    mod.addIncludePath(try frameworkRoot.join(b.allocator, "Headers"));
    mod.addLibraryPath(try frameworkRoot.join(b.allocator, "lib"));
    mod.linkSystemLibrary("python3.13", .{});

    const tree_sitter = b.dependency("tree_sitter", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("tree_sitter", tree_sitter.module("tree_sitter"));
    mod.addCSourceFiles(.{
        .files = &[_][]const u8{
            "tree-sitter-python/src/parser.c",
            "tree-sitter-python/src/scanner.c",
        },
    });

    const lib = b.addLibrary(.{
        .name = "example_python_library",
        .root_module = mod,
        .linkage = .dynamic,
    });
    const lib_tests = b.addTest(.{
        .name = "example_python_library_tests",
        .root_module = mod,
    });

    const build_step = b.step("lib", "Build the library.");
    const build_cmd = b.addInstallArtifact(lib, .{});
    build_step.dependOn(&build_cmd.step);
    build_cmd.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Test the library.");
    const test_cmd = b.addRunArtifact(lib_tests);
    test_step.dependOn(&test_cmd.step);
    if (b.args) |args| {
        test_cmd.addArgs(args);
    }
}
