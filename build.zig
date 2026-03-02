const std = @import("std");

fn createRootModuleFromFile(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options: *std.Build.Step.Options,
    root_source_file: []const u8,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path(root_source_file),
        .target = target,
        .optimize = optimize,
    });
    module.addOptions("build_options", build_options);
    return module;
}

fn createRootModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options: *std.Build.Step.Options,
) *std.Build.Module {
    return createRootModuleFromFile(
        b,
        target,
        optimize,
        build_options,
        "src/main.zig",
    );
}

fn addStaticLibraryCompat(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options: *std.Build.Step.Options,
    enable_experimental_sme: bool,
) *std.Build.Step.Compile {
    const lib = if (@hasDecl(std.Build, "addStaticLibrary"))
        b.addStaticLibrary(.{
            .name = "turbotoken",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        })
    else
        b.addLibrary(.{
            .name = "turbotoken",
            .linkage = .static,
            .root_module = createRootModule(b, target, optimize, build_options),
        });

    lib.root_module.addOptions("build_options", build_options);
    if (target.result.os.tag != .freestanding) {
        lib.linkLibC();
    }
    if (target.result.cpu.arch == .aarch64) {
        lib.root_module.addAssemblyFile(b.path("asm/arm64/neon_pretokenizer.S"));
        lib.root_module.addAssemblyFile(b.path("asm/arm64/neon_decoder.S"));
        lib.root_module.addAssemblyFile(b.path("asm/arm64/hash_crc32.S"));
        if (enable_experimental_sme) {
            lib.root_module.addAssemblyFile(b.path("asm/arm64/sme_pretokenizer.S"));
        }
    }

    return lib;
}

fn addSharedLibraryCompat(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options: *std.Build.Step.Options,
    enable_experimental_sme: bool,
) *std.Build.Step.Compile {
    const lib = if (@hasDecl(std.Build, "addSharedLibrary"))
        b.addSharedLibrary(.{
            .name = "turbotoken",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        })
    else
        b.addLibrary(.{
            .name = "turbotoken",
            .linkage = .dynamic,
            .root_module = createRootModule(b, target, optimize, build_options),
        });

    lib.root_module.addOptions("build_options", build_options);
    if (target.result.os.tag != .freestanding) {
        lib.linkLibC();
    }
    if (target.result.cpu.arch == .aarch64) {
        lib.root_module.addAssemblyFile(b.path("asm/arm64/neon_pretokenizer.S"));
        lib.root_module.addAssemblyFile(b.path("asm/arm64/neon_decoder.S"));
        lib.root_module.addAssemblyFile(b.path("asm/arm64/hash_crc32.S"));
        if (enable_experimental_sme) {
            lib.root_module.addAssemblyFile(b.path("asm/arm64/sme_pretokenizer.S"));
        }
    }

    return lib;
}

fn addTestCompat(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options: *std.Build.Step.Options,
    enable_experimental_sme: bool,
) *std.Build.Step.Compile {
    const tests = if (@hasField(std.Build.TestOptions, "root_source_file"))
        b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        })
    else
        b.addTest(.{
            .root_module = createRootModule(b, target, optimize, build_options),
        });

    tests.root_module.addOptions("build_options", build_options);
    if (target.result.os.tag != .freestanding) {
        tests.linkLibC();
    }
    if (target.result.cpu.arch == .aarch64) {
        tests.root_module.addAssemblyFile(b.path("asm/arm64/neon_pretokenizer.S"));
        tests.root_module.addAssemblyFile(b.path("asm/arm64/neon_decoder.S"));
        tests.root_module.addAssemblyFile(b.path("asm/arm64/hash_crc32.S"));
        if (enable_experimental_sme) {
            tests.root_module.addAssemblyFile(b.path("asm/arm64/sme_pretokenizer.S"));
        }
    }

    return tests;
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
    build_options: *std.Build.Step.Options,
    enable_experimental_sme: bool,
) *std.Build.Step {
    const lib = addStaticLibraryCompat(
        b,
        b.resolveTargetQuery(spec.query),
        optimize,
        build_options,
        enable_experimental_sme,
    );

    const step = b.step(spec.step_name, spec.description);
    step.dependOn(&lib.step);
    return step;
}

fn addWasmModuleStep(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    build_options: *std.Build.Step.Options,
) *std.Build.Step {
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const root_module = createRootModule(b, wasm_target, optimize, build_options);
    const wasm_exe = b.addExecutable(.{
        .name = "turbotoken",
        .root_module = root_module,
    });
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;
    wasm_exe.export_memory = true;
    wasm_exe.import_memory = false;
    wasm_exe.stack_size = 8 * 1024 * 1024;
    wasm_exe.initial_memory = 16 * 1024 * 1024;

    const install_wasm = b.addInstallArtifact(wasm_exe, .{});

    const npm_root_module = createRootModuleFromFile(
        b,
        wasm_target,
        optimize,
        build_options,
        "src/main_wasm_npm.zig",
    );
    const wasm_npm_exe = b.addExecutable(.{
        .name = "turbotoken-npm",
        .root_module = npm_root_module,
    });
    wasm_npm_exe.entry = .disabled;
    wasm_npm_exe.rdynamic = true;
    wasm_npm_exe.export_memory = true;
    wasm_npm_exe.import_memory = false;
    wasm_npm_exe.stack_size = 1 * 1024 * 1024;
    wasm_npm_exe.initial_memory = 2 * 1024 * 1024;

    const install_wasm_npm = b.addInstallArtifact(wasm_npm_exe, .{});
    const step = b.step("wasm", "Build WebAssembly module (zig-out/bin/turbotoken.wasm)");
    step.dependOn(&install_wasm.step);
    step.dependOn(&install_wasm_npm.step);
    return step;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_experimental_sme = b.option(
        bool,
        "experimental-sme",
        "Enable experimental ARM64 SME non-ASCII count kernel",
    ) orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_experimental_sme", enable_experimental_sme);

    const lib = addStaticLibraryCompat(
        b,
        target,
        optimize,
        build_options,
        enable_experimental_sme,
    );
    b.installArtifact(lib);

    const is_wasm_freestanding = target.result.cpu.arch == .wasm32 and target.result.os.tag == .freestanding;
    if (!is_wasm_freestanding) {
        const shared_lib = addSharedLibraryCompat(
            b,
            target,
            optimize,
            build_options,
            enable_experimental_sme,
        );
        b.installArtifact(shared_lib);
    }

    const tests = addTestCompat(
        b,
        target,
        optimize,
        build_options,
        enable_experimental_sme,
    );

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
        const step = addCrossTargetStep(
            b,
            optimize,
            spec,
            build_options,
            enable_experimental_sme,
        );
        targets_step.dependOn(step);
    }

    _ = addWasmModuleStep(
        b,
        optimize,
        build_options,
    );
}
