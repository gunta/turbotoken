#!/usr/bin/env bun
import { runCommand, section } from "./_lib";

const scripts = [
  "scripts/generate-fixture.ts",
  "scripts/bench-startup.ts",
  "scripts/bench-count.ts",
  "scripts/bench-encode.ts",
  "scripts/bench-decode.ts",
  "scripts/bench-throughput.ts",
  "scripts/bench-bigfile.ts",
  "scripts/bench-parallel.ts",
  "scripts/bench-comparison.ts",
  "scripts/bench-scalar-fallback.ts",
  "scripts/bench-native-pretokenizer.ts",
  "scripts/bench-native-byte-path.ts",
  "scripts/bench-ram.ts",
  "scripts/bench-binary-size.ts",
  "scripts/bench-wasm.ts",
  "scripts/bench-gpu.ts",
  "scripts/bench-gpu-crossover.ts",
  "scripts/generate-charts.ts",
];

let failures = 0;

for (const script of scripts) {
  section(`Running ${script}`);
  const result = runCommand("bun", ["run", script], { allowFailure: true });
  if (result.stdout.trim().length > 0) {
    console.log(result.stdout.trim());
  }
  if (result.stderr.trim().length > 0) {
    console.error(result.stderr.trim());
  }
  if (result.code !== 0) {
    failures += 1;
  }
}

if (failures > 0) {
  console.error(`bench-all finished with ${failures} failing script(s)`);
  process.exit(1);
}

console.log("bench-all completed successfully");
