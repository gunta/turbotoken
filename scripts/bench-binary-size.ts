#!/usr/bin/env bun
import { existsSync, statSync } from "node:fs";
import { resolvePath, runCommand, section, writeJson, commandExists } from "./_lib";

section("Binary size benchmark");

const outputPath = resolvePath("bench", "results", `bench-binary-size-${Date.now()}.json`);

if (!commandExists("zig")) {
  writeJson(outputPath, {
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: "zig not found on PATH",
  });
  console.warn("zig not found; wrote skipped benchmark record.");
  process.exit(0);
}

const targets = ["aarch64-macos", "aarch64-linux", "x86_64-linux", "wasm32-freestanding"];
const measurements: Array<{
  target: string;
  exitCode: number;
  artifactBytes: number | null;
  stdout: string;
  stderr: string;
}> = [];

for (const target of targets) {
  console.log(`Building target: ${target}`);
  const result = runCommand("zig", ["build", `-Dtarget=${target}`, "-Doptimize=ReleaseSmall"], {
    allowFailure: true,
  });

  const artifactPath = resolvePath("zig-out", "lib", "libturbotoken.a");
  const artifactBytes = existsSync(artifactPath) ? statSync(artifactPath).size : null;

  measurements.push({
    target,
    exitCode: result.code,
    artifactBytes,
    stdout: result.stdout,
    stderr: result.stderr,
  });
}

writeJson(outputPath, {
  generatedAt: new Date().toISOString(),
  measurements,
});

console.log(`Wrote binary size benchmark record: ${outputPath}`);
process.exit(0);
