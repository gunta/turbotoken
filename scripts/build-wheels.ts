#!/usr/bin/env bun
import { existsSync, readdirSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { commandExists, ensureDir, pythonExecutable, resolvePath, runCommand, section, writeJson, zigExecutable } from "./_lib";

interface TargetSpec {
  target: string;
  wheelTag: string;
  libRelativePath: string;
}

interface TargetBuildResult {
  target: string;
  wheelTag: string;
  libSourcePath: string;
  libBytes: number | null;
  crossBuildExitCode: number;
  crossBuildStdout: string;
  crossBuildStderr: string;
  repackExitCode: number | null;
  repackStdout: string;
  repackStderr: string;
  outputWheelPath: string | null;
  outputWheelBytes: number | null;
}

function replaceWheelTag(filename: string, wheelTag: string): string {
  const marker = "-py3-none-any.whl";
  if (!filename.endsWith(marker)) {
    throw new Error(`unexpected base wheel name: ${filename}`);
  }
  return `${filename.slice(0, -marker.length)}-py3-none-${wheelTag}.whl`;
}

function findBaseWheel(baseDir: string): string {
  const wheels = readdirSync(baseDir).filter((name) => name.endsWith(".whl")).sort();
  if (wheels.length === 0) {
    throw new Error(`no wheels produced in ${baseDir}`);
  }
  const candidate = wheels.find((name) => name.startsWith("turbotoken-")) ?? wheels[0];
  return join(baseDir, candidate);
}

section("Wheel build");

const python = pythonExecutable();
const zig = zigExecutable();
const outDir = resolvePath("dist", "wheels");
const baseDir = resolvePath("dist", "wheels", "base");
const nativeDir = resolvePath("dist", "wheels", "native");
ensureDir(outDir);
ensureDir(baseDir);
ensureDir(nativeDir);

const targets: TargetSpec[] = [
  { target: "aarch64-macos", wheelTag: "macosx_11_0_arm64", libRelativePath: "lib/libturbotoken.dylib" },
  { target: "aarch64-linux", wheelTag: "manylinux_2_17_aarch64", libRelativePath: "lib/libturbotoken.so" },
  { target: "x86_64-linux", wheelTag: "manylinux_2_17_x86_64", libRelativePath: "lib/libturbotoken.so" },
  { target: "x86_64-windows", wheelTag: "win_amd64", libRelativePath: "bin/turbotoken.dll" },
];

if (!commandExists(zig)) {
  console.error("zig is required for cross-target native builds");
  process.exit(1);
}

section("Build base wheel");
const baseWheelBuild = runCommand(
  python,
  ["-m", "pip", "wheel", ".", "--no-deps", "--wheel-dir", baseDir],
  { allowFailure: true },
);
if (baseWheelBuild.code !== 0) {
  console.error(baseWheelBuild.stderr.trim() || baseWheelBuild.stdout.trim());
  process.exit(baseWheelBuild.code);
}

const baseWheel = findBaseWheel(baseDir);
const baseWheelName = baseWheel.split("/").at(-1) ?? baseWheel;

const results: TargetBuildResult[] = [];
let failures = 0;

for (const item of targets) {
  section(`Cross-target native build: ${item.target}`);
  const prefix = resolvePath("dist", "wheels", "native", item.target);
  ensureDir(prefix);
  const crossBuild = runCommand(zig, ["build", `-Dtarget=${item.target}`, "--prefix", prefix], {
    allowFailure: true,
  });

  const libSourcePath = resolvePath("dist", "wheels", "native", item.target, item.libRelativePath);
  const libBytes = existsSync(libSourcePath) ? statSync(libSourcePath).size : null;

  let repackExitCode: number | null = null;
  let repackStdout = "";
  let repackStderr = "";
  let outputWheelPath: string | null = null;
  let outputWheelBytes: number | null = null;

  if (crossBuild.code === 0 && libBytes !== null) {
    const outputWheelName = replaceWheelTag(baseWheelName, item.wheelTag);
    outputWheelPath = resolvePath("dist", "wheels", outputWheelName);

    const repack = runCommand(
      python,
      [
        resolvePath("scripts", "repack-wheel.py"),
        "--base-wheel",
        baseWheel,
        "--output-wheel",
        outputWheelPath,
        "--lib-source",
        libSourcePath,
        "--lib-dest",
        `turbotoken/.libs/${item.libRelativePath.split("/").at(-1) ?? "libturbotoken"}`,
        "--wheel-tag",
        item.wheelTag,
      ],
      { allowFailure: true },
    );

    repackExitCode = repack.code;
    repackStdout = repack.stdout;
    repackStderr = repack.stderr;

    if (repack.code === 0 && outputWheelPath !== null && existsSync(outputWheelPath)) {
      outputWheelBytes = statSync(outputWheelPath).size;
    } else {
      failures += 1;
    }
  } else {
    failures += 1;
  }

  if (crossBuild.code !== 0) {
    failures += 1;
  }

  results.push({
    target: item.target,
    wheelTag: item.wheelTag,
    libSourcePath,
    libBytes,
    crossBuildExitCode: crossBuild.code,
    crossBuildStdout: crossBuild.stdout,
    crossBuildStderr: crossBuild.stderr,
    repackExitCode,
    repackStdout,
    repackStderr,
    outputWheelPath,
    outputWheelBytes,
  });
}

const metadataPath = resolvePath("dist", "wheels", `build-wheels-${Date.now()}.json`);
writeJson(metadataPath, {
  generatedAt: new Date().toISOString(),
  python,
  zig,
  baseWheel,
  targets: results,
  note: "Platform-tagged wheels are repacked from the base wheel with per-target native libraries under turbotoken/.libs.",
});

if (failures > 0) {
  console.error(`build-wheels completed with ${failures} failure(s)`);
  process.exit(1);
}

console.log(`Wrote wheel build metadata: ${metadataPath}`);
