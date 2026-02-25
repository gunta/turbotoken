#!/usr/bin/env bun
import { commandExists, runCommand, section, resolvePath, writeJson, zigExecutable } from "./_lib";

const outputPath = resolvePath("bench", "results", `build-all-${Date.now()}.json`);
const zig = zigExecutable();

if (!commandExists(zig)) {
  writeJson(outputPath, {
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: "zig executable not found",
  });
  console.warn("zig executable not found; wrote skipped build record.");
  process.exit(0);
}

const targets = ["aarch64-macos", "aarch64-linux", "x86_64-linux", "wasm32-freestanding"];
const results: Array<{ command: string; exitCode: number; stdout: string; stderr: string }> = [];

section("Host build");
const hostBuild = runCommand(zig, ["build"], { allowFailure: true });
results.push({ command: `${zig} build`, exitCode: hostBuild.code, stdout: hostBuild.stdout, stderr: hostBuild.stderr });

section("Host tests");
const hostTest = runCommand(zig, ["build", "test"], { allowFailure: true });
results.push({
  command: `${zig} build test`,
  exitCode: hostTest.code,
  stdout: hostTest.stdout,
  stderr: hostTest.stderr,
});

for (const target of targets) {
  section(`Cross target build: ${target}`);
  const result = runCommand(zig, ["build", `-Dtarget=${target}`], { allowFailure: true });
  results.push({
    command: `${zig} build -Dtarget=${target}`,
    exitCode: result.code,
    stdout: result.stdout,
    stderr: result.stderr,
  });
}

writeJson(outputPath, {
  generatedAt: new Date().toISOString(),
  results,
});

const failures = results.filter((item) => item.exitCode !== 0).length;
if (failures > 0) {
  console.error(`build-all completed with ${failures} failing command(s)`);
  process.exit(1);
}

console.log("build-all completed successfully");
process.exit(0);
