#!/usr/bin/env bun
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { resolvePath, runCommand, section, writeJson } from "./_lib";

type JsonMap = Record<string, unknown>;

function isRecord(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null;
}

function toNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function latestResultPath(prefix: string): string | null {
  const dir = resolvePath("bench", "results");
  const rows = readdirSync(dir)
    .filter((name) => name.startsWith(`${prefix}-`) && name.endsWith(".json") && !name.endsWith(".meta.json"))
    .sort();
  if (rows.length === 0) {
    return null;
  }
  return join(dir, rows[rows.length - 1]);
}

function latestResultPathSince(prefix: string, minTimestamp: number): string | null {
  const dir = resolvePath("bench", "results");
  const names = readdirSync(dir)
    .filter((name) => name.startsWith(`${prefix}-`) && name.endsWith(".json") && !name.endsWith(".meta.json"));
  let winner: { ts: number; path: string } | null = null;
  for (const name of names) {
    const match = name.match(new RegExp(`^${prefix}-(\\d+)\\.json$`));
    if (!match) {
      continue;
    }
    const ts = Number.parseInt(match[1], 10);
    if (!Number.isFinite(ts) || ts < minTimestamp) {
      continue;
    }
    if (!winner || ts > winner.ts) {
      winner = { ts, path: join(dir, name) };
    }
  }
  return winner?.path ?? null;
}

function loadJson(path: string | null): JsonMap | null {
  if (!path) {
    return null;
  }
  try {
    return JSON.parse(readFileSync(path, "utf8")) as JsonMap;
  } catch {
    return null;
  }
}

function extractCrossover(payload: JsonMap | null): JsonMap | null {
  if (!payload) {
    return null;
  }
  const rows = payload["bpe_rows"];
  if (!Array.isArray(rows) || rows.length === 0) {
    return null;
  }
  const wanted = rows
    .filter(isRecord)
    .filter((row) => toNumber(row["bytes"]) != null)
    .sort((a, b) => (toNumber(a["bytes"]) ?? 0) - (toNumber(b["bytes"]) ?? 0))
    .pop();
  if (!wanted) {
    return null;
  }
  return {
    bytes: toNumber(wanted["bytes"]),
    metalMs: toNumber(wanted["metal_gpu_ms"]),
    metalMiBPerSec: toNumber(wanted["metal_gpu_mib_per_s"]),
    autoMs: toNumber(wanted["auto_gpu_ms"]),
    autoMiBPerSec: toNumber(wanted["auto_gpu_mib_per_s"]),
    metalMatchesBaseline: wanted["metal_matches_baseline"] === true,
    routeBackend: wanted["route_backend"],
  };
}

function extractGpuMemory(payload: JsonMap | null): JsonMap | null {
  if (!payload) {
    return null;
  }
  const rows = payload["rows"];
  if (!Array.isArray(rows)) {
    return null;
  }
  const routeRow = rows.find((item) => isRecord(item) && item["name"] === "metal-bpe-route-encode-gpu");
  const directRow = rows.find((item) => isRecord(item) && item["name"] === "metal-bpe-direct-encode-1mb");
  if (!isRecord(routeRow) && !isRecord(directRow)) {
    return null;
  }
  const route = isRecord(routeRow)
    ? {
      inputBytes: toNumber((routeRow["workload"] as JsonMap | undefined)?.["input_bytes"]),
      medianGpuMs: toNumber(routeRow["median_gpu_ms"]),
      medianGpuMiBPerSec: toNumber(routeRow["median_gpu_mib_per_s"]),
      maxDeviceAllocatedMiB: toNumber(routeRow["max_device_allocated_mib"]),
      routeKindCounts: routeRow["route_kind_counts"],
    }
    : null;
  const direct = isRecord(directRow)
    ? {
      medianGpuMs: toNumber(directRow["median_gpu_ms"]),
      medianGpuMiBPerSec: toNumber(directRow["median_gpu_mib_per_s"]),
      maxDeviceAllocatedMiB: toNumber(directRow["max_device_allocated_mib"]),
    }
    : null;
  return {
    route,
    direct,
  };
}

function runScenario(enableDirect: boolean): JsonMap {
  const env: Record<string, string> = {
    TURBOTOKEN_METAL_BPE_DIRECT_ENABLE: enableDirect ? "1" : "0",
    TURBOTOKEN_GPU_CROSSOVER_QUICK: "1",
    TURBOTOKEN_GPU_MEMORY_RUNS: "1",
    TURBOTOKEN_GPU_MEMORY_SKIP_DIRECT_KERNEL: "1",
    TURBOTOKEN_GPU_MEMORY_ROUTE_BYTES: "262144",
  };
  if (process.env.TURBOTOKEN_METAL_BPE_DIRECT_LOW_ENTROPY_GUARD) {
    env.TURBOTOKEN_METAL_BPE_DIRECT_LOW_ENTROPY_GUARD = process.env.TURBOTOKEN_METAL_BPE_DIRECT_LOW_ENTROPY_GUARD;
  }
  if (process.env.TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT) {
    env.TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT = process.env.TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT;
  }
  const startedAt = Date.now();

  section(`GPU BPE direct scenario: TURBOTOKEN_METAL_BPE_DIRECT_ENABLE=${env.TURBOTOKEN_METAL_BPE_DIRECT_ENABLE}`);
  const crossoverRun = runCommand("bun", ["run", "scripts/bench-gpu-crossover.ts"], {
    env,
    allowFailure: true,
    timeoutMs: 15 * 60 * 1000,
  });
  if (crossoverRun.code !== 0) {
    throw new Error(crossoverRun.stderr || crossoverRun.stdout || "bench-gpu-crossover failed");
  }

  const gpuMemoryRun = runCommand("bun", ["run", "scripts/bench-gpu-memory.ts"], {
    env,
    allowFailure: true,
    timeoutMs: 10 * 60 * 1000,
  });
  if (gpuMemoryRun.code !== 0) {
    throw new Error(gpuMemoryRun.stderr || gpuMemoryRun.stdout || "bench-gpu-memory failed");
  }

  const crossoverPath = latestResultPathSince("bench-gpu-crossover", startedAt) ?? latestResultPath("bench-gpu-crossover");
  const memoryPath = latestResultPathSince("bench-gpu-memory", startedAt) ?? latestResultPath("bench-gpu-memory");
  return {
    enabled: enableDirect,
    env,
    artifacts: {
      crossover: crossoverPath,
      gpuMemory: memoryPath,
    },
    crossover: extractCrossover(loadJson(crossoverPath)),
    gpuMemory: extractGpuMemory(loadJson(memoryPath)),
  };
}

section("GPU BPE direct A/B benchmark");
const outputPath = resolvePath("bench", "results", `bench-gpu-bpe-direct-${Date.now()}.json`);

const disabled = runScenario(false);
const enabled = runScenario(true);

writeJson(outputPath, {
  tool: "gpu-bpe-direct-bench",
  generatedAt: new Date().toISOString(),
  note: "A/B run for true on-GPU BPE direct merge route vs host-stitched path.",
  scenarios: {
    disabled,
    enabled,
  },
});

console.log(`Wrote GPU BPE direct A/B benchmark: ${outputPath}`);
