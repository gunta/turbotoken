#!/usr/bin/env bun
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { acquireBenchmarkLock, resolvePath, section, writeJson } from "./_lib";

type JsonMap = Record<string, unknown>;

type Metrics = {
  artifactPath: string;
  meanWallMs: number;
  meanHostOverheadMs: number;
  medianGpuMs: number;
  gpuMiBPerS: number | null;
  directRouteCount: number;
  matchesBaseline: boolean;
};

type CandidateResult = {
  stage: string;
  name: string;
  env: Record<string, string>;
  metrics: Metrics;
};

function isRecord(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null;
}

function toNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function parseResultPath(stdout: string): string | null {
  const match = stdout.match(/Wrote GPU host-overhead artifact:\s*(.+)\s*$/m);
  if (!match) {
    return null;
  }
  return match[1].trim();
}

function parseDirectCount(value: unknown): number {
  if (!isRecord(value)) {
    return 0;
  }
  const direct = toNumber(value["direct"]);
  return direct == null ? 0 : Math.max(0, Math.floor(direct));
}

function loadMetrics(path: string): Metrics {
  const payload = JSON.parse(readFileSync(path, "utf8")) as JsonMap;
  const status = typeof payload["status"] === "string" ? String(payload["status"]) : "ok";
  if (status !== "ok") {
    const reason = typeof payload["reason"] === "string" ? payload["reason"] : `status=${status}`;
    throw new Error(`host-overhead benchmark not runnable (${reason})`);
  }
  const rows = Array.isArray(payload["rows"]) ? payload["rows"].filter(isRecord) : [];
  const enabled = rows.find((row) => String(row["name"] ?? "") === "route-normal-text-direct-enabled");
  if (!enabled) {
    throw new Error("missing route-normal-text-direct-enabled row in host-overhead artifact");
  }
  const meanWallMs = toNumber(enabled["mean_wall_ms"]);
  const meanHostMs = toNumber(enabled["mean_host_overhead_ms"]);
  const medianGpuMs = toNumber(enabled["median_gpu_ms"]);
  if (meanWallMs == null || meanHostMs == null || medianGpuMs == null) {
    throw new Error("incomplete normal-text direct-enabled metrics in host-overhead artifact");
  }
  return {
    artifactPath: path,
    meanWallMs,
    meanHostOverheadMs: meanHostMs,
    medianGpuMs,
    gpuMiBPerS: toNumber(enabled["gpu_mib_per_s"]),
    directRouteCount: parseDirectCount(enabled["route_kind_counts"]),
    matchesBaseline: enabled["matches_baseline"] === true,
  };
}

function envSignature(env: Record<string, string>): string {
  return JSON.stringify(Object.keys(env).sort().reduce((acc, key) => {
    acc[key] = env[key];
    return acc;
  }, {} as Record<string, string>));
}

function better(a: CandidateResult, b: CandidateResult): CandidateResult {
  if (a.metrics.matchesBaseline !== b.metrics.matchesBaseline) {
    return a.metrics.matchesBaseline ? a : b;
  }
  if (a.metrics.directRouteCount !== b.metrics.directRouteCount) {
    return a.metrics.directRouteCount > b.metrics.directRouteCount ? a : b;
  }
  if (a.metrics.meanWallMs !== b.metrics.meanWallMs) {
    return a.metrics.meanWallMs < b.metrics.meanWallMs ? a : b;
  }
  if (a.metrics.meanHostOverheadMs !== b.metrics.meanHostOverheadMs) {
    return a.metrics.meanHostOverheadMs < b.metrics.meanHostOverheadMs ? a : b;
  }
  const aGpu = a.metrics.gpuMiBPerS ?? -1;
  const bGpu = b.metrics.gpuMiBPerS ?? -1;
  return aGpu >= bGpu ? a : b;
}

function latestHostOverheadResultSince(minTimestamp: number): string | null {
  const dir = resolvePath("bench", "results");
  const files = readdirSync(dir)
    .filter((name) => name.startsWith("bench-gpu-host-overhead-") && name.endsWith(".json"));
  let winner: { ts: number; path: string } | null = null;
  for (const name of files) {
    const match = name.match(/^bench-gpu-host-overhead-(\d+)\.json$/);
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

function runHostOverheadCandidate(
  stage: string,
  name: string,
  envOverrides: Record<string, string>,
  runDefaults: Record<string, string>,
): CandidateResult {
  const startedAt = Date.now();
  const env = {
    ...runDefaults,
    ...envOverrides,
  };

  console.log(`\n[${stage}] ${name}`);
  const run = Bun.spawnSync({
    cmd: ["bun", "run", "scripts/bench-gpu-host-overhead.ts"],
    cwd: resolvePath(),
    env: {
      ...process.env,
      ...env,
    },
    stdout: "pipe",
    stderr: "pipe",
  });
  const stdout = new TextDecoder().decode(run.stdout).trim();
  const stderr = new TextDecoder().decode(run.stderr).trim();
  if (stdout.length > 0) {
    console.log(stdout);
  }
  if (stderr.length > 0) {
    console.error(stderr);
  }
  if (run.exitCode !== 0) {
    throw new Error(`[${stage}] ${name} failed (exit ${run.exitCode ?? 1})`);
  }

  let artifactPath = parseResultPath(stdout);
  if (!artifactPath) {
    artifactPath = latestHostOverheadResultSince(startedAt);
  }
  if (!artifactPath) {
    throw new Error(`[${stage}] ${name} did not produce a host-overhead artifact`);
  }

  const metrics = loadMetrics(artifactPath);
  console.log(
    `[${stage}] ${name} => wall=${metrics.meanWallMs.toFixed(3)} ms host=${metrics.meanHostOverheadMs.toFixed(3)} ms gpu=${metrics.medianGpuMs.toFixed(3)} ms gpuMiB/s=${metrics.gpuMiBPerS == null ? "n/a" : metrics.gpuMiBPerS.toFixed(3)} direct=${metrics.directRouteCount} match=${metrics.matchesBaseline}`,
  );

  return {
    stage,
    name,
    env,
    metrics,
  };
}

function uniqueSortedNumbers(values: number[]): number[] {
  const uniq = Array.from(new Set(values.filter((value) => Number.isFinite(value) && value > 0).map((value) => Math.floor(value))));
  uniq.sort((a, b) => a - b);
  return uniq;
}

function threadBundle(threads: number): Record<string, string> {
  const t = String(threads);
  return {
    TURBOTOKEN_METAL_BPE_FIND_THREADS: t,
    TURBOTOKEN_METAL_BPE_MARK_THREADS: t,
    TURBOTOKEN_METAL_BPE_APPLY_THREADS: t,
    TURBOTOKEN_METAL_BPE_COMPACT_THREADS: t,
  };
}

section("GPU BPE knob sweep");
const lock = acquireBenchmarkLock({ label: "bench-gpu-knob-sweep" });
try {
  const runDefaults: Record<string, string> = {
    TURBOTOKEN_BENCH_SPEED: "full",
    TURBOTOKEN_GPU_HOST_OVERHEAD_BYTES: process.env.TURBOTOKEN_GPU_HOST_OVERHEAD_BYTES ?? "1048576",
    TURBOTOKEN_GPU_HOST_OVERHEAD_ROUTE_LOOPS: process.env.TURBOTOKEN_GPU_HOST_OVERHEAD_ROUTE_LOOPS ?? "4",
    TURBOTOKEN_GPU_HOST_OVERHEAD_DIGEST_LOOPS: process.env.TURBOTOKEN_GPU_HOST_OVERHEAD_DIGEST_LOOPS ?? "512",
    TURBOTOKEN_GPU_HOST_OVERHEAD_INCLUDE_STRESS: process.env.TURBOTOKEN_GPU_HOST_OVERHEAD_INCLUDE_STRESS ?? "0",
    TURBOTOKEN_METAL_BPE_ACTIVE_COMPACT_ENABLE: process.env.TURBOTOKEN_METAL_BPE_ACTIVE_COMPACT_ENABLE ?? "1",
  };

  const allResults: CandidateResult[] = [];
  const bySignature = new Map<string, CandidateResult>();

  const addResult = (result: CandidateResult): CandidateResult => {
    const sig = envSignature(result.env);
    const existing = bySignature.get(sig);
    if (!existing) {
      bySignature.set(sig, result);
      allResults.push(result);
      return result;
    }
    const winner = better(existing, result);
    bySignature.set(sig, winner);
    if (winner !== existing) {
      const idx = allResults.indexOf(existing);
      if (idx >= 0) {
        allResults[idx] = winner;
      }
      return winner;
    }
    return existing;
  };

  const baseline = addResult(runHostOverheadCandidate("baseline", "default", {}, runDefaults));

  let best = baseline;

  const stage1Threads = [32, 64, 96, 128, 160, 192, 224, 256, 320];
  for (const threads of stage1Threads) {
    const candidate = addResult(
      runHostOverheadCandidate(
        "stage1-threads",
        `bundle-${threads}`,
        threadBundle(threads),
        runDefaults,
      ),
    );
    best = better(best, candidate);
  }

  const roundsCandidates = [12, 16, 20, 24, 28, 32, 40];
  for (const rounds of roundsCandidates) {
    const candidate = addResult(
      runHostOverheadCandidate(
        "stage2-rounds",
        `rounds-${rounds}`,
        {
          ...threadBundle(Number.parseInt(best.env.TURBOTOKEN_METAL_BPE_FIND_THREADS ?? "128", 10) || 128),
          TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT: String(rounds),
        },
        runDefaults,
      ),
    );
    best = better(best, candidate);
  }

  const strideCandidates = [1, 2, 3, 4, 5, 6, 8];
  for (const stride of strideCandidates) {
    const candidate = addResult(
      runHostOverheadCandidate(
        "stage3-compact-stride",
        `stride-${stride}`,
        {
          ...threadBundle(Number.parseInt(best.env.TURBOTOKEN_METAL_BPE_FIND_THREADS ?? "128", 10) || 128),
          TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT: best.env.TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT ?? "24",
          TURBOTOKEN_METAL_BPE_ACTIVE_COMPACT_STRIDE: String(stride),
        },
        runDefaults,
      ),
    );
    best = better(best, candidate);
  }

  const bestThread = Number.parseInt(best.env.TURBOTOKEN_METAL_BPE_FIND_THREADS ?? "128", 10) || 128;
  const threadNeighborhood = uniqueSortedNumbers([bestThread - 64, bestThread - 32, bestThread, bestThread + 32, bestThread + 64]);

  const tuneOne = (
    stage: string,
    key: "TURBOTOKEN_METAL_BPE_FIND_THREADS" | "TURBOTOKEN_METAL_BPE_MARK_THREADS" | "TURBOTOKEN_METAL_BPE_APPLY_THREADS" | "TURBOTOKEN_METAL_BPE_COMPACT_THREADS",
  ) => {
    for (const value of threadNeighborhood) {
      const candidateEnv: Record<string, string> = {
        TURBOTOKEN_METAL_BPE_FIND_THREADS: best.env.TURBOTOKEN_METAL_BPE_FIND_THREADS ?? String(bestThread),
        TURBOTOKEN_METAL_BPE_MARK_THREADS: best.env.TURBOTOKEN_METAL_BPE_MARK_THREADS ?? String(bestThread),
        TURBOTOKEN_METAL_BPE_APPLY_THREADS: best.env.TURBOTOKEN_METAL_BPE_APPLY_THREADS ?? String(bestThread),
        TURBOTOKEN_METAL_BPE_COMPACT_THREADS: best.env.TURBOTOKEN_METAL_BPE_COMPACT_THREADS ?? String(bestThread),
      };
      candidateEnv[key] = String(value);
      if (best.env.TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT) {
        candidateEnv.TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT = best.env.TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT;
      }
      if (best.env.TURBOTOKEN_METAL_BPE_ACTIVE_COMPACT_STRIDE) {
        candidateEnv.TURBOTOKEN_METAL_BPE_ACTIVE_COMPACT_STRIDE = best.env.TURBOTOKEN_METAL_BPE_ACTIVE_COMPACT_STRIDE;
      }
      const candidate = addResult(
        runHostOverheadCandidate(stage, `${key.split("_").at(-2)?.toLowerCase() ?? "kernel"}-${value}`, candidateEnv, runDefaults),
      );
      best = better(best, candidate);
    }
  };

  tuneOne("stage4-find", "TURBOTOKEN_METAL_BPE_FIND_THREADS");
  tuneOne("stage4-mark", "TURBOTOKEN_METAL_BPE_MARK_THREADS");
  tuneOne("stage4-apply", "TURBOTOKEN_METAL_BPE_APPLY_THREADS");
  tuneOne("stage4-compact", "TURBOTOKEN_METAL_BPE_COMPACT_THREADS");

  // Final validation pass on the selected best config with stress rows enabled.
  const finalValidation = runHostOverheadCandidate(
    "validation",
    "best-with-stress",
    {
      ...Object.fromEntries(Object.entries(best.env).filter(([key]) => key.startsWith("TURBOTOKEN_METAL_"))),
      TURBOTOKEN_GPU_HOST_OVERHEAD_INCLUDE_STRESS: "1",
    },
    {
      ...runDefaults,
      TURBOTOKEN_GPU_HOST_OVERHEAD_INCLUDE_STRESS: "1",
    },
  );

  const ranked = [...allResults].sort((left, right) => {
    if (left.metrics.meanWallMs !== right.metrics.meanWallMs) {
      return left.metrics.meanWallMs - right.metrics.meanWallMs;
    }
    if (left.metrics.meanHostOverheadMs !== right.metrics.meanHostOverheadMs) {
      return left.metrics.meanHostOverheadMs - right.metrics.meanHostOverheadMs;
    }
    const lg = left.metrics.gpuMiBPerS ?? -1;
    const rg = right.metrics.gpuMiBPerS ?? -1;
    return rg - lg;
  });

  const baselineWall = baseline.metrics.meanWallMs;
  const baselineHost = baseline.metrics.meanHostOverheadMs;

  const summary = ranked.slice(0, 12).map((row, index) => ({
    rank: index + 1,
    stage: row.stage,
    name: row.name,
    wallMs: row.metrics.meanWallMs,
    hostOverheadMs: row.metrics.meanHostOverheadMs,
    gpuMs: row.metrics.medianGpuMs,
    gpuMiBPerS: row.metrics.gpuMiBPerS,
    wallSpeedupVsBaseline: baselineWall > 0 ? baselineWall / row.metrics.meanWallMs : null,
    hostOverheadReductionPctVsBaseline:
      baselineHost > 0 ? ((baselineHost - row.metrics.meanHostOverheadMs) / baselineHost) * 100.0 : null,
    directRouteCount: row.metrics.directRouteCount,
    matchesBaseline: row.metrics.matchesBaseline,
    env: row.env,
    artifactPath: row.metrics.artifactPath,
  }));

  const output = {
    tool: "gpu-knob-sweep",
    generatedAt: new Date().toISOString(),
    runDefaults,
    totalCandidates: ranked.length,
    baseline: {
      name: baseline.name,
      stage: baseline.stage,
      wallMs: baseline.metrics.meanWallMs,
      hostOverheadMs: baseline.metrics.meanHostOverheadMs,
      gpuMs: baseline.metrics.medianGpuMs,
      gpuMiBPerS: baseline.metrics.gpuMiBPerS,
      env: baseline.env,
      artifactPath: baseline.metrics.artifactPath,
    },
    best: {
      name: best.name,
      stage: best.stage,
      wallMs: best.metrics.meanWallMs,
      hostOverheadMs: best.metrics.meanHostOverheadMs,
      gpuMs: best.metrics.medianGpuMs,
      gpuMiBPerS: best.metrics.gpuMiBPerS,
      wallSpeedupVsBaseline: baselineWall > 0 ? baselineWall / best.metrics.meanWallMs : null,
      hostOverheadReductionPctVsBaseline:
        baselineHost > 0 ? ((baselineHost - best.metrics.meanHostOverheadMs) / baselineHost) * 100.0 : null,
      env: best.env,
      artifactPath: best.metrics.artifactPath,
    },
    top: summary,
    validation: {
      stage: finalValidation.stage,
      name: finalValidation.name,
      wallMs: finalValidation.metrics.meanWallMs,
      hostOverheadMs: finalValidation.metrics.meanHostOverheadMs,
      gpuMs: finalValidation.metrics.medianGpuMs,
      gpuMiBPerS: finalValidation.metrics.gpuMiBPerS,
      directRouteCount: finalValidation.metrics.directRouteCount,
      matchesBaseline: finalValidation.metrics.matchesBaseline,
      artifactPath: finalValidation.metrics.artifactPath,
    },
    all: ranked.map((row) => ({
      stage: row.stage,
      name: row.name,
      wallMs: row.metrics.meanWallMs,
      hostOverheadMs: row.metrics.meanHostOverheadMs,
      gpuMs: row.metrics.medianGpuMs,
      gpuMiBPerS: row.metrics.gpuMiBPerS,
      directRouteCount: row.metrics.directRouteCount,
      matchesBaseline: row.metrics.matchesBaseline,
      env: row.env,
      artifactPath: row.metrics.artifactPath,
    })),
    note:
      "Sweep objective: minimize route-normal-text-direct-enabled mean wall time from bench-gpu-host-overhead while preserving parity and direct-route usage.",
  };

  const outputPath = resolvePath("bench", "results", `bench-gpu-knob-sweep-${Date.now()}.json`);
  writeJson(outputPath, output);

  console.log("\n== Sweep Summary ==");
  console.log(`Baseline wall: ${baseline.metrics.meanWallMs.toFixed(3)} ms`);
  console.log(`Best wall: ${best.metrics.meanWallMs.toFixed(3)} ms (${(baselineWall / best.metrics.meanWallMs).toFixed(3)}x faster vs baseline)`);
  console.log(
    `Best host overhead: ${best.metrics.meanHostOverheadMs.toFixed(3)} ms (${(((baselineHost - best.metrics.meanHostOverheadMs) / baselineHost) * 100.0).toFixed(2)}% lower vs baseline)`,
  );
  console.log(`Best artifact: ${best.metrics.artifactPath}`);
  console.log(`Sweep artifact: ${outputPath}`);
} finally {
  lock.release();
}
