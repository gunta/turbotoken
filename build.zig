const std = @import("std");

fn createRootModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
}

fn addStaticLibraryCompat(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    if (@hasDecl(std.Build, "addStaticLibrary")) {
        return b.addStaticLibrary(.{
            .name = "turbotoken",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
    }

    return b.addLibrary(.{
        .name = "turbotoken",
        .linkage = .static,
        .root_module = createRootModule(b, target, optimize),
    });
}

fn addSharedLibraryCompat(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    if (@hasDecl(std.Build, "addSharedLibrary")) {
        return b.addSharedLibrary(.{
            .name = "turbotoken",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
    }

    return b.addLibrary(.{
        .name = "turbotoken",
        .linkage = .dynamic,
        .root_module = createRootModule(b, target, optimize),
    });
}

fn addTestCompat(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    if (@hasField(std.Build.TestOptions, "root_source_file")) {
        return b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
    }

    return b.addTest(.{
        .root_module = createRootModule(b, target, optimize),
    });
}

const BuildTargetSpec = struct {
    step_name: []const u8,
    description: []const u8,
    query: std.Target.Query,
};

fn addCrossTargetStep(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    spec: BuildTargetSpec,
) *std.Build.Step {
    const lib = addStaticLibraryCompat(
        b,
        b.resolveTargetQuery(spec.query),
        optimize,
    );

    const step = b.step(spec.step_name, spec.description);
    step.dependOn(&lib.step);
    return step;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = addStaticLibraryCompat(b, target, optimize);
    b.installArtifact(lib);

    const is_wasm_freestanding = target.result.cpu.arch == .wasm32 and target.result.os.tag == .freestanding;
    if (!is_wasm_freestanding) {
        const shared_lib = addSharedLibraryCompat(b, target, optimize);
        b.installArtifact(shared_lib);
    }

    const tests = addTestCompat(b, target, optimize);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run turbotoken unit tests");
    test_step.dependOn(&run_tests.step);

    const cross_targets = [_]BuildTargetSpec{
        .{
            .step_name = "lib-aarch64-macos",
            .description = "Build static library for aarch64-macos",
            .query = .{
                .cpu_arch = .aarch64,
                .os_tag = .macos,
            },
        },
        .{
            .step_name = "lib-aarch64-linux",
            .description = "Build static library for aarch64-linux",
            .query = .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
            },
        },
        .{
            .step_name = "lib-x86_64-linux",
            .description = "Build static library for x86_64-linux",
            .query = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
            },
        },
        .{
            .step_name = "lib-wasm32-freestanding",
            .description = "Build static library for wasm32-freestanding",
            .query = .{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
            },
        },
    };

    const targets_step = b.step("targets", "Build all planned cross-target libraries");
    inline for (cross_targets) |spec| {
        const step = addCrossTargetStep(b, optimize, spec);
        targets_step.dependOn(step);
    }
}
