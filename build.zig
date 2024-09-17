const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

    const exe = b.addExecutable(.{
        .name = "mcm",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mibu_dep = b.dependency("mibu", .{
        .target = target,
        .optimize = optimize,
    });
    const zig_toml_dep = b.dependency("zig-toml", .{
        .target = target,
        .optimize = optimize,
    });
    const tmpfile_dep = b.dependency("tmpfile", .{});

    exe.root_module.addImport("mibu", mibu_dep.module("mibu"));
    exe.root_module.addImport("zig-toml", zig_toml_dep.module("zig-toml"));
    exe.root_module.addImport("tmpfile", tmpfile_dep.module("tmpfile"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
