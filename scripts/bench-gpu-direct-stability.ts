#!/usr/bin/env bun
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { acquireBenchmarkLock, benchSpeedProfile, resolvePath, runCommand, section, writeJson } from "./_lib";

type JsonMap = Record<string, unknown>;

function isRecord(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null;
}

function toNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function parseIntOrDefault(raw: string | undefined, fallback: number, minimum = 1): number {
  if (!raw) {
    return fallback;
  }
  const value = Number.parseInt(raw, 10);
  if (!Number.isFinite(value) || value < minimum) {
    return fallback;
  }
  return value;
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

function parseArtifactPathFromStdout(stdout: string): string | null {
  const match = stdout.match(/Wrote GPU BPE direct A\/B benchmark:\s*(.+)\s*$/m);
  return match?.[1]?.trim() ?? null;
}

function loadJson(path: string): JsonMap {
  return JSON.parse(readFileSync(path, "utf8")) as JsonMap;
}

function median(values: number[]): number | null {
  if (values.length === 0) {
    return null;
  }
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

function p95(values: number[]): number | null {
  if (values.length === 0) {
    return null;
  }
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.max(0, Math.min(sorted.length - 1, Math.ceil(sorted.length * 0.95) - 1));
  return sorted[idx];
}

interface WorkloadAccumulator {
  samples: number;
  slowdownPct: number[];
  throughputRatio: number[];
  enabledRouteMedianGpuMiBPerSec: number[];
  disabledRouteMedianGpuMiBPerSec: number[];
  enabledRouteMedianBpeRounds: number[];
  disabledRouteMedianBpeRounds: number[];
  enabledRouteMedianBpeSubmits: number[];
  disabledRouteMedianBpeSubmits: number[];
  enabledUsedDirectRouteTrueCount: number;
  disabledUsedDirectRouteTrueCount: number;
  enabledMatchesBaselineTrueCount: number;
  disabledMatchesBaselineTrueCount: number;
}

function emptyAccumulator(): WorkloadAccumulator {
  return {
    samples: 0,
    slowdownPct: [],
    throughputRatio: [],
    enabledRouteMedianGpuMiBPerSec: [],
    disabledRouteMedianGpuMiBPerSec: [],
    enabledRouteMedianBpeRounds: [],
    disabledRouteMedianBpeRounds: [],
    enabledRouteMedianBpeSubmits: [],
    disabledRouteMedianBpeSubmits: [],
    enabledUsedDirectRouteTrueCount: 0,
    disabledUsedDirectRouteTrueCount: 0,
    enabledMatchesBaselineTrueCount: 0,
    disabledMatchesBaselineTrueCount: 0,
  };
}

function runPass(runIndex: number, runs: number): { artifactPath: string; payload: JsonMap } {
  section(`Direct A/B stability pass ${runIndex + 1}/${runs}`);
  const startedAt = Date.now();
  const run = runCommand("bun", ["run", "scripts/bench-gpu-bpe-direct.ts"], {
    allowFailure: true,
    timeoutMs: 45 * 60 * 1000,
  });
  if (run.code !== 0) {
    throw new Error(run.stderr || run.stdout || `bench-gpu-bpe-direct failed with code ${run.code}`);
  }
  const artifactPath = parseArtifactPathFromStdout(run.stdout)
    ?? latestResultPathSince("bench-gpu-bpe-direct", startedAt);
  if (!artifactPath) {
    throw new Error("unable to locate bench-gpu-bpe-direct artifact after stability pass");
  }
  return {
    artifactPath,
    payload: loadJson(artifactPath),
  };
}

section("GPU direct-route stability harness");
const lock = acquireBenchmarkLock({ label: "bench-gpu-direct-stability" });
try {
  const speedProfile = benchSpeedProfile();
  const defaultRuns = speedProfile === "fast" ? 3 : 7;
  const runs = parseIntOrDefault(process.env.TURBOTOKEN_GPU_DIRECT_STABILITY_RUNS, defaultRuns);
  const passArtifacts: string[] = [];
  const aggregates = new Map<string, WorkloadAccumulator>();

  for (let idx = 0; idx < runs; idx += 1) {
    const pass = runPass(idx, runs);
    passArtifacts.push(pass.artifactPath);

    const workloads = pass.payload["workloads"];
    if (!isRecord(workloads)) {
      continue;
    }
    for (const [workloadKey, workloadValue] of Object.entries(workloads)) {
      if (!isRecord(workloadValue)) {
        continue;
      }
      const comparison = workloadValue["comparison"];
      if (!isRecord(comparison)) {
        continue;
      }
      const acc = aggregates.get(workloadKey) ?? emptyAccumulator();
      acc.samples += 1;
      const slowdownPct = toNumber(comparison["slowdownPct"]);
      const throughputRatio = toNumber(comparison["throughputRatio"]);
      const enabledRouteMedianGpuMiBPerSec = toNumber(comparison["enabledRouteMedianGpuMiBPerSec"]);
      const disabledRouteMedianGpuMiBPerSec = toNumber(comparison["disabledRouteMedianGpuMiBPerSec"]);
      const enabledRouteMedianBpeRounds = toNumber(comparison["enabledRouteMedianBpeRounds"]);
      const disabledRouteMedianBpeRounds = toNumber(comparison["disabledRouteMedianBpeRounds"]);
      const enabledRouteMedianBpeSubmits = toNumber(comparison["enabledRouteMedianBpeSubmits"]);
      const disabledRouteMedianBpeSubmits = toNumber(comparison["disabledRouteMedianBpeSubmits"]);

      if (slowdownPct != null) {
        acc.slowdownPct.push(slowdownPct);
      }
      if (throughputRatio != null) {
        acc.throughputRatio.push(throughputRatio);
      }
      if (enabledRouteMedianGpuMiBPerSec != null) {
        acc.enabledRouteMedianGpuMiBPerSec.push(enabledRouteMedianGpuMiBPerSec);
      }
      if (disabledRouteMedianGpuMiBPerSec != null) {
        acc.disabledRouteMedianGpuMiBPerSec.push(disabledRouteMedianGpuMiBPerSec);
      }
      if (enabledRouteMedianBpeRounds != null) {
        acc.enabledRouteMedianBpeRounds.push(enabledRouteMedianBpeRounds);
      }
      if (disabledRouteMedianBpeRounds != null) {
        acc.disabledRouteMedianBpeRounds.push(disabledRouteMedianBpeRounds);
      }
      if (enabledRouteMedianBpeSubmits != null) {
        acc.enabledRouteMedianBpeSubmits.push(enabledRouteMedianBpeSubmits);
      }
      if (disabledRouteMedianBpeSubmits != null) {
        acc.disabledRouteMedianBpeSubmits.push(disabledRouteMedianBpeSubmits);
      }
      if (comparison["enabledUsedDirectRoute"] === true) {
        acc.enabledUsedDirectRouteTrueCount += 1;
      }
      if (comparison["disabledUsedDirectRoute"] === true) {
        acc.disabledUsedDirectRouteTrueCount += 1;
      }
      if (comparison["enabledMatchesBaseline"] === true) {
        acc.enabledMatchesBaselineTrueCount += 1;
      }
      if (comparison["disabledMatchesBaseline"] === true) {
        acc.disabledMatchesBaselineTrueCount += 1;
      }

      aggregates.set(workloadKey, acc);
    }
  }

  const summaryByWorkload: JsonMap = {};
  for (const [workloadKey, acc] of aggregates.entries()) {
    summaryByWorkload[workloadKey] = {
      samples: acc.samples,
      slowdownPct: {
        median: median(acc.slowdownPct),
        p95: p95(acc.slowdownPct),
      },
      throughputRatio: {
        median: median(acc.throughputRatio),
        p95: p95(acc.throughputRatio),
      },
      enabledRouteMedianGpuMiBPerSec: {
        median: median(acc.enabledRouteMedianGpuMiBPerSec),
        p95: p95(acc.enabledRouteMedianGpuMiBPerSec),
      },
      disabledRouteMedianGpuMiBPerSec: {
        median: median(acc.disabledRouteMedianGpuMiBPerSec),
        p95: p95(acc.disabledRouteMedianGpuMiBPerSec),
      },
      enabledRouteMedianBpeRounds: {
        median: median(acc.enabledRouteMedianBpeRounds),
        p95: p95(acc.enabledRouteMedianBpeRounds),
      },
      disabledRouteMedianBpeRounds: {
        median: median(acc.disabledRouteMedianBpeRounds),
        p95: p95(acc.disabledRouteMedianBpeRounds),
      },
      enabledRouteMedianBpeSubmits: {
        median: median(acc.enabledRouteMedianBpeSubmits),
        p95: p95(acc.enabledRouteMedianBpeSubmits),
      },
      disabledRouteMedianBpeSubmits: {
        median: median(acc.disabledRouteMedianBpeSubmits),
        p95: p95(acc.disabledRouteMedianBpeSubmits),
      },
      enabledUsedDirectRouteTrueCount: acc.enabledUsedDirectRouteTrueCount,
      disabledUsedDirectRouteTrueCount: acc.disabledUsedDirectRouteTrueCount,
      enabledMatchesBaselineTrueCount: acc.enabledMatchesBaselineTrueCount,
      disabledMatchesBaselineTrueCount: acc.disabledMatchesBaselineTrueCount,
      enabledMatchesBaselineAll: acc.samples > 0 && acc.enabledMatchesBaselineTrueCount === acc.samples,
      disabledMatchesBaselineAll: acc.samples > 0 && acc.disabledMatchesBaselineTrueCount === acc.samples,
    };
  }

  const outputPath = resolvePath("bench", "results", `bench-gpu-direct-stability-${Date.now()}.json`);
  writeJson(outputPath, {
    tool: "gpu-bpe-direct-stability",
    generatedAt: new Date().toISOString(),
    speedProfile,
    runsRequested: runs,
    runsCompleted: passArtifacts.length,
    passArtifacts,
    summaryByWorkload,
    note: "Repeated direct A/B harness; reports median and p95 across runs for slowdown/throughput and direct-route profile telemetry.",
  });
  console.log(`Wrote GPU direct-route stability benchmark: ${outputPath}`);
} finally {
  lock.release();
}

process.exit(0);
