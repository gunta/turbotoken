#!/usr/bin/env bun
import { existsSync, statSync } from "node:fs";
import { commandExists, resolvePath, runCommand, section, writeJson, zigExecutable } from "./_lib";

section("WASM benchmark");

const outputPath = resolvePath("bench", "results", `bench-wasm-${Date.now()}.json`);
const zig = zigExecutable();

if (!commandExists(zig)) {
  writeJson(outputPath, {
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: "zig executable not found",
  });
  console.warn("zig executable not found; wrote skipped benchmark record.");
  process.exit(0);
}

const buildResult = runCommand(
  zig,
  ["build", "-Dtarget=wasm32-freestanding", "-Doptimize=ReleaseSmall"],
  { allowFailure: true },
);

const artifactPath = resolvePath("zig-out", "lib", "libturbotoken.a");
const artifactBytes = existsSync(artifactPath) ? statSync(artifactPath).size : null;

writeJson(outputPath, {
  generatedAt: new Date().toISOString(),
  target: "wasm32-freestanding",
  exitCode: buildResult.code,
  artifactPath,
  artifactBytes,
  stdout: buildResult.stdout,
  stderr: buildResult.stderr,
  note: "Current wasm benchmark records build artifact size only; runtime wasm encode benchmark remains TODO.",
});

console.log(`Wrote WASM benchmark record: ${outputPath}`);
if (buildResult.code !== 0) {
  console.warn("WASM build failed; result was recorded as scaffold status.");
}
process.exit(0);
