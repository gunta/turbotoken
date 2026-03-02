const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the turbotoken dependency
    const turbotoken_dep = b.dependency("turbotoken", .{
        .target = target,
        .optimize = optimize,
    });
    const turbotoken_mod = turbotoken_dep.module("turbotoken");

    // Build the CLI executable
    const exe = b.addExecutable(.{
        .name = "turbotoken",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("turbotoken", turbotoken_mod);

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the turbotoken CLI");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("tests/cli_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("turbotoken", turbotoken_mod);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run CLI tests");
    test_step.dependOn(&run_tests.step);
}
