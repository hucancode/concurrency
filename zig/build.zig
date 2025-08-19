const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const exe = b.addExecutable(.{
        .name = "blur_zig",
        .root_source_file = b.path("blur.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Compile STB wrapper
    exe.addCSourceFile(.{
        .file = b.path("stb_wrapper.c"),
        .flags = &.{"-std=c99"},
    });
    
    // Add STB image libraries
    exe.addIncludePath(b.path("."));
    exe.linkLibC();
    
    // Install the executable
    b.installArtifact(exe);
    
    // Create run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    
    const run_step = b.step("run", "Run the blur application");
    run_step.dependOn(&run_cmd.step);
}