#!/usr/bin/env bun
import { resolvePath, section, writeJson } from "./_lib";

section("GPU benchmark");

const isAvailableResult = Bun.spawnSync({
  cmd: [
    "python3",
    "-c",
    "import sys;sys.path.insert(0,'python');from turbotoken import _gpu; raise SystemExit(0 if _gpu.available() else 1)",
  ],
  cwd: resolvePath(),
  stdout: "pipe",
  stderr: "pipe",
});

const outputPath = resolvePath("bench", "results", `bench-gpu-${Date.now()}.json`);

if (isAvailableResult.exitCode !== 0) {
  const payload = {
    tool: "gpu-bench",
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: "GPU backend reports unavailable",
  };
  writeJson(outputPath, payload);
  console.log("GPU backend unavailable; wrote skip record.");
  process.exit(0);
}

const payload = {
  tool: "gpu-bench",
  generatedAt: new Date().toISOString(),
  status: "not-implemented",
  reason: "GPU kernels exist as experiments; benchmark harness still pending runtime integration.",
};
writeJson(outputPath, payload);
console.log(`Wrote GPU placeholder benchmark record: ${outputPath}`);
process.exit(0);
