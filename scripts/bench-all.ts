#!/usr/bin/env bun
import { resolvePath, runCommand, section, withBenchmarkLock, writeJson } from "./_lib";

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
  "scripts/bench-competitors.ts",
  "scripts/bench-chat.ts",
  "scripts/bench-training.ts",
  "scripts/bench-scalar-fallback.ts",
  "scripts/bench-pair-cache-hash.ts",
  "scripts/bench-encoder-queue.ts",
  "scripts/bench-native-pretokenizer.ts",
  "scripts/bench-boundary-classifier.ts",
  "scripts/bench-native-byte-path.ts",
  "scripts/bench-ram.ts",
  "scripts/bench-binary-size.ts",
  "scripts/bench-wasm.ts",
  "scripts/bench-gpu.ts",
  "scripts/bench-gpu-memory.ts",
  "scripts/bench-gpu-crossover.ts",
  "scripts/bench-gpu-overlap.ts",
  "scripts/generate-charts.ts",
  "scripts/bench-scorecard.ts",
];

const includeCuda = ["1", "true", "yes", "on"].includes(
  (process.env.TURBOTOKEN_BENCH_INCLUDE_CUDA ?? "").trim().toLowerCase(),
);

if (includeCuda) {
  const crossoverIndex = scripts.indexOf("scripts/bench-gpu-crossover.ts");
  const insertAt = crossoverIndex >= 0 ? crossoverIndex : scripts.length;
  scripts.splice(insertAt, 0, "scripts/bench-gpu-memory-cuda.ts");
} else {
  console.log("Skipping CUDA benchmark by default (set TURBOTOKEN_BENCH_INCLUDE_CUDA=1 to enable)");
}

let failures = 0;
const startedAt = Date.now();
const stepRows: Array<{
  script: string;
  exitCode: number;
  startedAt: string;
  finishedAt: string;
  elapsedMs: number;
}> = [];

withBenchmarkLock("bench-all", () => {
  for (const script of scripts) {
    section(`Running ${script}`);
    const stepStart = Date.now();
    const result = runCommand("bun", ["run", script], { allowFailure: true });
    const stepEnd = Date.now();
    stepRows.push({
      script,
      exitCode: result.code,
      startedAt: new Date(stepStart).toISOString(),
      finishedAt: new Date(stepEnd).toISOString(),
      elapsedMs: stepEnd - stepStart,
    });
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
});

const finishedAt = Date.now();
const queuePath = resolvePath("bench", "results", `bench-queue-${finishedAt}.json`);
writeJson(queuePath, {
  tool: "bench-queue",
  generatedAt: new Date().toISOString(),
  startedAt: new Date(startedAt).toISOString(),
  finishedAt: new Date(finishedAt).toISOString(),
  elapsedMs: finishedAt - startedAt,
  includeCuda,
  failures,
  steps: stepRows,
  note: "Sequential local benchmark queue with machine lock. Remote benchmarks should run on separate hosts/runners.",
});
console.log(`Wrote benchmark queue record: ${queuePath}`);

if (failures > 0) {
  console.error(`bench-all finished with ${failures} failing script(s)`);
  process.exit(1);
}

console.log("bench-all completed successfully");
