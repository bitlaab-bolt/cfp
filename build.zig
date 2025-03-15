const std = @import("std");
const builtin = @import("builtin");


pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe
    });

    // Exposing as a dependency for other projects
    const pkg = b.addModule("cfp", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize
    });

    // Making executable for this project
    const exe = b.addExecutable(.{
        .name = "cfp",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Self importing package
    exe.root_module.addImport("cfp", pkg);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&b.addRunArtifact(exe).step);
}