const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Main executable (supports both blur and kuwahara)
    const exe = b.addExecutable(.{
        .name = "filter_zig",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    exe.addCSourceFile(.{
        .file = b.path("stb_wrapper.c"),
        .flags = &.{"-std=c99"},
    });
    
    exe.addIncludePath(b.path("."));
    exe.linkLibC();
    b.installArtifact(exe);
    
    // Create run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the filter application");
    run_step.dependOn(&run_cmd.step);
}