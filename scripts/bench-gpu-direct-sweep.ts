#!/usr/bin/env bun
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { acquireBenchmarkLock, resolvePath, section, writeJson } from "./_lib";

type JsonMap = Record<string, unknown>;
type WorkloadKey = "lowEntropy" | "normalText" | "lowEntropyLong" | "normalTextLong";

interface Candidate {
  name: string;
  env: Record<string, string>;
}

interface WorkloadScoreRow {
  key: WorkloadKey;
  throughputRatio: number;
  slowdownPct: number | null;
  enabledUsedDirectRoute: boolean | null;
  disabledUsedDirectRoute: boolean | null;
  enabledMatchesBaseline: boolean;
  disabledMatchesBaseline: boolean;
}

interface ScoreBreakdown {
  score: number;
  weightedRatio: number;
  penalty: number;
  parityOk: boolean;
  longNormalThroughputRatio: number | null;
  rows: WorkloadScoreRow[];
}

interface CandidateRun {
  stage: string;
  name: string;
  env: Record<string, string>;
  selectedWorkloads: WorkloadKey[];
  artifactPath: string;
  score: ScoreBreakdown;
}

const SHORT_SCREEN_WORKLOADS: WorkloadKey[] = ["normalText", "normalTextLong"];
const FULL_WORKLOADS: WorkloadKey[] = ["lowEntropy", "normalText", "lowEntropyLong", "normalTextLong"];

const STAGE1_WEIGHTS: Record<WorkloadKey, number> = {
  lowEntropy: 0,
  normalText: 0.30,
  lowEntropyLong: 0,
  normalTextLong: 0.70,
};

const FULL_WEIGHTS: Record<WorkloadKey, number> = {
  lowEntropy: 0.05,
  normalText: 0.20,
  lowEntropyLong: 0.15,
  normalTextLong: 0.60,
};

function isRecord(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null;
}

function toNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function parseOutputPath(stdout: string): string | null {
  const match = stdout.match(/Wrote GPU BPE direct A\/B benchmark:\s*(.+)\s*$/m);
  if (!match) {
    return null;
  }
  return match[1].trim();
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

function parseWorkloadRows(payload: JsonMap, keys: WorkloadKey[]): WorkloadScoreRow[] {
  const workloadsRaw = payload["workloads"];
  if (!isRecord(workloadsRaw)) {
    return [];
  }
  const rows: WorkloadScoreRow[] = [];
  for (const key of keys) {
    const row = workloadsRaw[key];
    if (!isRecord(row)) {
      continue;
    }
    const comparison = row["comparison"];
    if (!isRecord(comparison)) {
      continue;
    }
    const throughputRatio = toNumber(comparison["throughputRatio"]);
    if (throughputRatio == null || throughputRatio <= 0) {
      continue;
    }
    rows.push({
      key,
      throughputRatio,
      slowdownPct: toNumber(comparison["slowdownPct"]),
      enabledUsedDirectRoute:
        typeof comparison["enabledUsedDirectRoute"] === "boolean"
          ? (comparison["enabledUsedDirectRoute"] as boolean)
          : null,
      disabledUsedDirectRoute:
        typeof comparison["disabledUsedDirectRoute"] === "boolean"
          ? (comparison["disabledUsedDirectRoute"] as boolean)
          : null,
      enabledMatchesBaseline: comparison["enabledMatchesBaseline"] === true,
      disabledMatchesBaseline: comparison["disabledMatchesBaseline"] === true,
    });
  }
  return rows;
}

function scoreRows(rows: WorkloadScoreRow[], weights: Record<WorkloadKey, number>): ScoreBreakdown {
  let weightedRatio = 0;
  let penalty = 0;
  let parityOk = true;
  let longNormalRatio: number | null = null;

  const byKey = new Map(rows.map((row) => [row.key, row]));
  for (const [key, weight] of Object.entries(weights) as [WorkloadKey, number][]) {
    if (weight <= 0) {
      continue;
    }
    const row = byKey.get(key);
    if (!row) {
      penalty += weight * 2.0;
      parityOk = false;
      continue;
    }

    if (!row.enabledMatchesBaseline || !row.disabledMatchesBaseline) {
      parityOk = false;
      penalty += weight * 4.0;
      continue;
    }

    weightedRatio += weight * row.throughputRatio;

    if (row.throughputRatio < 1.0) {
      penalty += weight * (1.0 - row.throughputRatio) * 3.0;
    }

    if (key === "normalTextLong") {
      longNormalRatio = row.throughputRatio;
      if (row.enabledUsedDirectRoute === false) {
        penalty += 0.35;
      }
    }

    if (key === "normalText" && row.throughputRatio < 0.9) {
      penalty += 0.15;
    }

    if (key === "lowEntropy" && row.throughputRatio < 0.85) {
      penalty += 0.10;
    }
  }

  const score = (weightedRatio * 100.0) - (penalty * 100.0);
  return {
    score,
    weightedRatio,
    penalty,
    parityOk,
    longNormalThroughputRatio: longNormalRatio,
    rows,
  };
}

function runCandidate(
  stage: string,
  candidate: Candidate,
  selectedWorkloads: WorkloadKey[],
  commonEnv: Record<string, string>,
): CandidateRun {
  section(`[${stage}] ${candidate.name}`);
  const startedAt = Date.now();
  const env = {
    ...commonEnv,
    ...candidate.env,
    TURBOTOKEN_GPU_BPE_DIRECT_WORKLOADS: selectedWorkloads.join(","),
  };

  const run = Bun.spawnSync({
    cmd: ["bun", "run", "scripts/bench-gpu-bpe-direct.ts"],
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
    throw new Error(`[${stage}] ${candidate.name} failed with exit ${run.exitCode ?? 1}`);
  }

  let artifactPath = parseOutputPath(stdout);
  if (!artifactPath) {
    artifactPath = latestResultPathSince("bench-gpu-bpe-direct", startedAt);
  }
  if (!artifactPath) {
    throw new Error(`[${stage}] ${candidate.name} did not produce bench-gpu-bpe-direct artifact`);
  }

  const payload = JSON.parse(readFileSync(artifactPath, "utf8")) as JsonMap;
  const rows = parseWorkloadRows(payload, selectedWorkloads);
  const score = scoreRows(rows, selectedWorkloads.length === SHORT_SCREEN_WORKLOADS.length ? STAGE1_WEIGHTS : FULL_WEIGHTS);

  console.log(
    `[${stage}] ${candidate.name} => score=${score.score.toFixed(3)} weightedRatio=${score.weightedRatio.toFixed(4)} penalty=${score.penalty.toFixed(4)} longNormalRatio=${score.longNormalThroughputRatio == null ? "n/a" : score.longNormalThroughputRatio.toFixed(4)}`,
  );

  return {
    stage,
    name: candidate.name,
    env,
    selectedWorkloads,
    artifactPath,
    score,
  };
}

function rankRuns(runs: CandidateRun[]): CandidateRun[] {
  return [...runs].sort((left, right) => {
    if (left.score.parityOk !== right.score.parityOk) {
      return left.score.parityOk ? -1 : 1;
    }
    if (left.score.score !== right.score.score) {
      return right.score.score - left.score.score;
    }
    if ((left.score.longNormalThroughputRatio ?? -1) !== (right.score.longNormalThroughputRatio ?? -1)) {
      return (right.score.longNormalThroughputRatio ?? -1) - (left.score.longNormalThroughputRatio ?? -1);
    }
    return left.name.localeCompare(right.name);
  });
}

section("GPU direct-objective sweep");
const lock = acquireBenchmarkLock({ label: "bench-gpu-direct-sweep" });
try {
  const baseEnv: Record<string, string> = {
    TURBOTOKEN_METAL_BPE_ACTIVE_COMPACT_ENABLE: "1",
    TURBOTOKEN_METAL_BPE_ACTIVE_COMPACT_STRIDE: "8",
    TURBOTOKEN_METAL_BPE_FIND_THREADS: "224",
    TURBOTOKEN_METAL_BPE_MARK_THREADS: "256",
    TURBOTOKEN_METAL_BPE_APPLY_THREADS: "256",
    TURBOTOKEN_METAL_BPE_COMPACT_THREADS: "288",
    TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT: "32",
  };

  const commonEnv: Record<string, string> = {
    TURBOTOKEN_BENCH_SPEED: process.env.TURBOTOKEN_BENCH_SPEED ?? "full",
    TURBOTOKEN_GPU_CROSSOVER_QUICK: process.env.TURBOTOKEN_GPU_CROSSOVER_QUICK ?? "1",
    TURBOTOKEN_GPU_MEMORY_RUNS: process.env.TURBOTOKEN_GPU_MEMORY_RUNS ?? "1",
    TURBOTOKEN_GPU_MEMORY_SKIP_DIRECT_KERNEL: process.env.TURBOTOKEN_GPU_MEMORY_SKIP_DIRECT_KERNEL ?? "1",
  };

  const candidates: Candidate[] = [
    { name: "default", env: {} },
    { name: "base", env: { ...baseEnv } },
    { name: "base-compact-192", env: { ...baseEnv, TURBOTOKEN_METAL_BPE_COMPACT_THREADS: "192" } },
    { name: "base-compact-256", env: { ...baseEnv, TURBOTOKEN_METAL_BPE_COMPACT_THREADS: "256" } },
    { name: "base-rounds-28", env: { ...baseEnv, TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT: "28" } },
    { name: "base-rounds-40", env: { ...baseEnv, TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT: "40" } },
    { name: "base-find-192", env: { ...baseEnv, TURBOTOKEN_METAL_BPE_FIND_THREADS: "192" } },
    { name: "base-find-256", env: { ...baseEnv, TURBOTOKEN_METAL_BPE_FIND_THREADS: "256" } },
    { name: "base-mark-320", env: { ...baseEnv, TURBOTOKEN_METAL_BPE_MARK_THREADS: "320" } },
    { name: "base-apply-320", env: { ...baseEnv, TURBOTOKEN_METAL_BPE_APPLY_THREADS: "320" } },
  ];

  const stage1Runs: CandidateRun[] = [];
  for (const candidate of candidates) {
    stage1Runs.push(runCandidate("stage1-screen", candidate, SHORT_SCREEN_WORKLOADS, commonEnv));
  }

  const rankedStage1 = rankRuns(stage1Runs);
  const topStage1 = rankedStage1.slice(0, 3);

  const stage2Candidates: Candidate[] = topStage1.map((row) => ({
    name: row.name,
    env: Object.fromEntries(Object.entries(row.env).filter(([key]) => key.startsWith("TURBOTOKEN_METAL_"))),
  }));

  if (!stage2Candidates.some((row) => row.name === "default")) {
    stage2Candidates.push({ name: "default", env: {} });
  }

  const stage2Runs: CandidateRun[] = [];
  for (const candidate of stage2Candidates) {
    stage2Runs.push(runCandidate("stage2-full", candidate, FULL_WORKLOADS, commonEnv));
  }

  const rankedStage2 = rankRuns(stage2Runs);
  const winner = rankedStage2[0];

  const output = {
    tool: "gpu-direct-objective-sweep",
    generatedAt: new Date().toISOString(),
    objective: "maximize weighted throughput ratio from bench-gpu-bpe-direct across short+long workloads while preserving parity",
    commonEnv,
    stage1: {
      workloads: SHORT_SCREEN_WORKLOADS,
      top: rankedStage1.slice(0, 5).map((row, index) => ({
        rank: index + 1,
        name: row.name,
        score: row.score.score,
        weightedRatio: row.score.weightedRatio,
        penalty: row.score.penalty,
        longNormalThroughputRatio: row.score.longNormalThroughputRatio,
        parityOk: row.score.parityOk,
        artifactPath: row.artifactPath,
        env: Object.fromEntries(Object.entries(row.env).filter(([key]) => key.startsWith("TURBOTOKEN_METAL_"))),
      })),
      all: rankedStage1.map((row) => ({
        name: row.name,
        score: row.score.score,
        weightedRatio: row.score.weightedRatio,
        penalty: row.score.penalty,
        longNormalThroughputRatio: row.score.longNormalThroughputRatio,
        parityOk: row.score.parityOk,
        artifactPath: row.artifactPath,
      })),
    },
    stage2: {
      workloads: FULL_WORKLOADS,
      ranking: rankedStage2.map((row, index) => ({
        rank: index + 1,
        name: row.name,
        score: row.score.score,
        weightedRatio: row.score.weightedRatio,
        penalty: row.score.penalty,
        longNormalThroughputRatio: row.score.longNormalThroughputRatio,
        parityOk: row.score.parityOk,
        artifactPath: row.artifactPath,
        env: Object.fromEntries(Object.entries(row.env).filter(([key]) => key.startsWith("TURBOTOKEN_METAL_"))),
        rows: row.score.rows,
      })),
      winner: winner
        ? {
          name: winner.name,
          score: winner.score.score,
          weightedRatio: winner.score.weightedRatio,
          penalty: winner.score.penalty,
          longNormalThroughputRatio: winner.score.longNormalThroughputRatio,
          parityOk: winner.score.parityOk,
          artifactPath: winner.artifactPath,
          env: Object.fromEntries(Object.entries(winner.env).filter(([key]) => key.startsWith("TURBOTOKEN_METAL_"))),
          rows: winner.score.rows,
        }
        : null,
    },
  };

  const outputPath = resolvePath("bench", "results", `bench-gpu-direct-objective-sweep-${Date.now()}.json`);
  writeJson(outputPath, output);

  section("Sweep summary");
  if (winner) {
    console.log(`Winner: ${winner.name}`);
    console.log(`Score: ${winner.score.score.toFixed(3)} (weightedRatio=${winner.score.weightedRatio.toFixed(4)} penalty=${winner.score.penalty.toFixed(4)})`);
    console.log(`Long normal throughput ratio: ${winner.score.longNormalThroughputRatio == null ? "n/a" : winner.score.longNormalThroughputRatio.toFixed(4)}`);
    console.log(`Winner artifact: ${winner.artifactPath}`);
  }
  console.log(`Sweep artifact: ${outputPath}`);
} finally {
  lock.release();
}
