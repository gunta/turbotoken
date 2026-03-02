#!/usr/bin/env bun
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { acquireBenchmarkLock, benchSpeedProfile, resolvePath, runCommand, section, writeJson } from "./_lib";

type JsonMap = Record<string, unknown>;
type TextKind = "low-entropy" | "normal-text";

interface WorkloadProfile {
  key: "lowEntropy" | "normalText" | "lowEntropyLong" | "normalTextLong";
  textKind: TextKind;
  inputBytes: number;
  lane: "short" | "long";
  description: string;
}

const WORKLOADS: WorkloadProfile[] = [
  {
    key: "lowEntropy",
    textKind: "low-entropy",
    inputBytes: 262_144,
    lane: "short",
    description: "Highly repetitive low-entropy text (safety guard stress path).",
  },
  {
    key: "normalText",
    textKind: "normal-text",
    inputBytes: 262_144,
    lane: "short",
    description: "Normal English fixture text slice.",
  },
  {
    key: "lowEntropyLong",
    textKind: "low-entropy",
    inputBytes: 1_048_576,
    lane: "long",
    description: "Long low-entropy direct-route lane (1MB) for true direct-GPU crossover tuning.",
  },
  {
    key: "normalTextLong",
    textKind: "normal-text",
    inputBytes: 1_048_576,
    lane: "long",
    description: "Long normal-text direct-route lane (1MB) for true direct-GPU crossover tuning.",
  },
];

const WORKLOAD_KEY_SET = new Set(WORKLOADS.map((row) => row.key));

function selectedWorkloads(): WorkloadProfile[] {
  const raw = (process.env.TURBOTOKEN_GPU_BPE_DIRECT_WORKLOADS ?? "").trim();
  if (!raw) {
    return WORKLOADS;
  }
  const wanted = new Set(
    raw
      .split(",")
      .map((part) => part.trim())
      .filter((part) => WORKLOAD_KEY_SET.has(part as WorkloadProfile["key"])) as WorkloadProfile["key"][],
  );
  if (wanted.size === 0) {
    return WORKLOADS;
  }
  return WORKLOADS.filter((row) => wanted.has(row.key));
}

function isRecord(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null;
}

function toNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function readEnvOrDefault(name: string, fallback: string): string {
  const raw = process.env[name]?.trim();
  return raw && raw.length > 0 ? raw : fallback;
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

function parseRouteKindCounts(value: unknown): Record<string, number> {
  if (!isRecord(value)) {
    return {};
  }
  const result: Record<string, number> = {};
  for (const [key, raw] of Object.entries(value)) {
    const numeric = toNumber(raw);
    if (numeric != null && numeric > 0) {
      result[key] = numeric;
    }
  }
  return result;
}

function percentIncrease(baseline: number | null, next: number | null): number | null {
  if (baseline == null || next == null || baseline <= 0) {
    return null;
  }
  return ((next - baseline) / baseline) * 100;
}

function ratio(baseline: number | null, next: number | null): number | null {
  if (baseline == null || next == null || baseline <= 0) {
    return null;
  }
  return next / baseline;
}

function extractCrossover(payload: JsonMap | null, textKind: TextKind): JsonMap | null {
  if (!payload) {
    return null;
  }
  const rowsRaw = payload["bpe_rows"];
  if (!Array.isArray(rowsRaw) || rowsRaw.length === 0) {
    return null;
  }
  const rows = rowsRaw.filter(isRecord);
  const withKind = rows.filter((row) => String(row["text_kind"] ?? "").trim() === textKind);
  const sourceRows = withKind.length > 0 ? withKind : rows;
  const wanted = sourceRows
    .filter(isRecord)
    .filter((row) => toNumber(row["bytes"]) != null)
    .sort((a, b) => (toNumber(a["bytes"]) ?? 0) - (toNumber(b["bytes"]) ?? 0))
    .pop();
  if (!wanted) {
    return null;
  }
  return {
    textKind: String(wanted["text_kind"] ?? textKind),
    bytes: toNumber(wanted["bytes"]),
    metalMs: toNumber(wanted["metal_gpu_ms"]),
    metalMiBPerSec: toNumber(wanted["metal_gpu_mib_per_s"]),
    metalBpeRounds: toNumber(wanted["metal_bpe_rounds"]),
    metalBpeSubmits: toNumber(wanted["metal_bpe_submits"]),
    autoMs: toNumber(wanted["auto_gpu_ms"]),
    autoMiBPerSec: toNumber(wanted["auto_gpu_mib_per_s"]),
    metalMatchesBaseline: wanted["metal_matches_baseline"] === true,
    routeBackend: wanted["route_backend"],
  };
}

function extractGpuMemory(payload: JsonMap | null, textKind: TextKind): JsonMap | null {
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
      textKind: String((routeRow["workload"] as JsonMap | undefined)?.["text_kind"] ?? textKind),
      medianGpuMs: toNumber(routeRow["median_gpu_ms"]),
      medianGpuMiBPerSec: toNumber(routeRow["median_gpu_mib_per_s"]),
      medianBpeRounds: toNumber(routeRow["median_bpe_rounds"]),
      medianBpeSubmits: toNumber(routeRow["median_bpe_submits"]),
      maxDeviceAllocatedMiB: toNumber(routeRow["max_device_allocated_mib"]),
      routeKindCounts: parseRouteKindCounts(routeRow["route_kind_counts"]),
    }
    : null;
  const direct = isRecord(directRow)
    ? {
      medianGpuMs: toNumber(directRow["median_gpu_ms"]),
      medianGpuMiBPerSec: toNumber(directRow["median_gpu_mib_per_s"]),
      medianBpeRounds: toNumber(directRow["median_bpe_rounds"]),
      medianBpeSubmits: toNumber(directRow["median_bpe_submits"]),
      maxDeviceAllocatedMiB: toNumber(directRow["max_device_allocated_mib"]),
    }
    : null;
  return {
    route,
    direct,
  };
}

function routeSummary(scenario: JsonMap | null): {
  routeKinds: Record<string, number>;
  usedDirectRoute: boolean | null;
  medianGpuMiBPerSec: number | null;
  medianBpeRounds: number | null;
  medianBpeSubmits: number | null;
  maxDeviceAllocatedMiB: number | null;
} {
  if (!scenario) {
    return {
      routeKinds: {},
      usedDirectRoute: null,
      medianGpuMiBPerSec: null,
      medianBpeRounds: null,
      medianBpeSubmits: null,
      maxDeviceAllocatedMiB: null,
    };
  }
  const gpuMemory = scenario["gpuMemory"];
  if (!isRecord(gpuMemory)) {
    return {
      routeKinds: {},
      usedDirectRoute: null,
      medianGpuMiBPerSec: null,
      medianBpeRounds: null,
      medianBpeSubmits: null,
      maxDeviceAllocatedMiB: null,
    };
  }
  const route = gpuMemory["route"];
  if (!isRecord(route)) {
    return {
      routeKinds: {},
      usedDirectRoute: null,
      medianGpuMiBPerSec: null,
      medianBpeRounds: null,
      medianBpeSubmits: null,
      maxDeviceAllocatedMiB: null,
    };
  }
  const routeKinds = parseRouteKindCounts(route["routeKindCounts"]);
  return {
    routeKinds,
    usedDirectRoute: Object.prototype.hasOwnProperty.call(routeKinds, "direct"),
    medianGpuMiBPerSec: toNumber(route["medianGpuMiBPerSec"]),
    medianBpeRounds: toNumber(route["medianBpeRounds"]),
    medianBpeSubmits: toNumber(route["medianBpeSubmits"]),
    maxDeviceAllocatedMiB: toNumber(route["maxDeviceAllocatedMiB"]),
  };
}

function compareScenarios(disabled: JsonMap, enabled: JsonMap): JsonMap {
  const disabledCrossover = isRecord(disabled["crossover"]) ? (disabled["crossover"] as JsonMap) : null;
  const enabledCrossover = isRecord(enabled["crossover"]) ? (enabled["crossover"] as JsonMap) : null;

  const disabledMs = toNumber(disabledCrossover?.["metalMs"]);
  const enabledMs = toNumber(enabledCrossover?.["metalMs"]);
  const disabledMiBPerSec = toNumber(disabledCrossover?.["metalMiBPerSec"]);
  const enabledMiBPerSec = toNumber(enabledCrossover?.["metalMiBPerSec"]);
  const disabledRounds = toNumber(disabledCrossover?.["metalBpeRounds"]);
  const enabledRounds = toNumber(enabledCrossover?.["metalBpeRounds"]);
  const disabledSubmits = toNumber(disabledCrossover?.["metalBpeSubmits"]);
  const enabledSubmits = toNumber(enabledCrossover?.["metalBpeSubmits"]);

  const disabledRoute = routeSummary(disabled);
  const enabledRoute = routeSummary(enabled);

  return {
    disabledMetalMs: disabledMs,
    enabledMetalMs: enabledMs,
    disabledMetalMiBPerSec: disabledMiBPerSec,
    enabledMetalMiBPerSec: enabledMiBPerSec,
    disabledMetalBpeRounds: disabledRounds,
    enabledMetalBpeRounds: enabledRounds,
    disabledMetalBpeSubmits: disabledSubmits,
    enabledMetalBpeSubmits: enabledSubmits,
    slowdownPct: percentIncrease(disabledMs, enabledMs),
    throughputRatio: ratio(disabledMiBPerSec, enabledMiBPerSec),
    throughputDropPct: percentIncrease(enabledMiBPerSec, disabledMiBPerSec),
    disabledMatchesBaseline: disabledCrossover?.["metalMatchesBaseline"] === true,
    enabledMatchesBaseline: enabledCrossover?.["metalMatchesBaseline"] === true,
    disabledRouteBackend: disabledCrossover?.["routeBackend"] ?? null,
    enabledRouteBackend: enabledCrossover?.["routeBackend"] ?? null,
    disabledRouteKinds: disabledRoute.routeKinds,
    enabledRouteKinds: enabledRoute.routeKinds,
    disabledUsedDirectRoute: disabledRoute.usedDirectRoute,
    enabledUsedDirectRoute: enabledRoute.usedDirectRoute,
    disabledRouteMedianGpuMiBPerSec: disabledRoute.medianGpuMiBPerSec,
    enabledRouteMedianGpuMiBPerSec: enabledRoute.medianGpuMiBPerSec,
    disabledRouteMedianBpeRounds: disabledRoute.medianBpeRounds,
    enabledRouteMedianBpeRounds: enabledRoute.medianBpeRounds,
    disabledRouteMedianBpeSubmits: disabledRoute.medianBpeSubmits,
    enabledRouteMedianBpeSubmits: enabledRoute.medianBpeSubmits,
    disabledRouteMaxDeviceAllocatedMiB: disabledRoute.maxDeviceAllocatedMiB,
    enabledRouteMaxDeviceAllocatedMiB: enabledRoute.maxDeviceAllocatedMiB,
  };
}

function runScenario(enableDirect: boolean, profile: WorkloadProfile): JsonMap {
  const bytesString = String(Math.max(1024, profile.inputBytes));
  const env: Record<string, string> = {
    TURBOTOKEN_METAL_BPE_DIRECT_ENABLE: enableDirect ? "1" : "0",
    TURBOTOKEN_GPU_CROSSOVER_QUICK: readEnvOrDefault("TURBOTOKEN_GPU_CROSSOVER_QUICK", "1"),
    TURBOTOKEN_GPU_MEMORY_RUNS: readEnvOrDefault("TURBOTOKEN_GPU_MEMORY_RUNS", "1"),
    TURBOTOKEN_GPU_MEMORY_SKIP_DIRECT_KERNEL: readEnvOrDefault("TURBOTOKEN_GPU_MEMORY_SKIP_DIRECT_KERNEL", "1"),
    TURBOTOKEN_GPU_MEMORY_ROUTE_BYTES: bytesString,
    TURBOTOKEN_GPU_CROSSOVER_BPE_BYTES: bytesString,
    TURBOTOKEN_GPU_CROSSOVER_BPE_TEXT_KIND: profile.textKind,
    TURBOTOKEN_GPU_MEMORY_ROUTE_TEXT_KIND: profile.textKind,
  };
  if (process.env.TURBOTOKEN_METAL_BPE_DIRECT_LOW_ENTROPY_GUARD) {
    env.TURBOTOKEN_METAL_BPE_DIRECT_LOW_ENTROPY_GUARD = process.env.TURBOTOKEN_METAL_BPE_DIRECT_LOW_ENTROPY_GUARD;
  }
  if (process.env.TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT) {
    env.TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT = process.env.TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT;
  }
  if (profile.lane === "long" && profile.textKind === "normal-text") {
    env.TURBOTOKEN_GPU_CROSSOVER_NORMAL_TEXT_MODE = "singlepiece-lower";
    env.TURBOTOKEN_GPU_MEMORY_NORMAL_TEXT_MODE = "singlepiece-lower";
  }
  const startedAt = Date.now();

  section(
    `GPU BPE direct scenario: text=${profile.textKind}, bytes=${bytesString}, TURBOTOKEN_METAL_BPE_DIRECT_ENABLE=${env.TURBOTOKEN_METAL_BPE_DIRECT_ENABLE}`,
  );
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
    lane: profile.lane,
    inputBytes: profile.inputBytes,
    env,
    artifacts: {
      crossover: crossoverPath,
      gpuMemory: memoryPath,
    },
    crossover: extractCrossover(loadJson(crossoverPath), profile.textKind),
    gpuMemory: extractGpuMemory(loadJson(memoryPath), profile.textKind),
  };
}

section("GPU BPE direct A/B benchmark");
acquireBenchmarkLock({ label: "bench-gpu-bpe-direct" });
const speedProfile = benchSpeedProfile();
const outputPath = resolvePath("bench", "results", `bench-gpu-bpe-direct-${Date.now()}.json`);
const workloadRows = selectedWorkloads();

const workloads: Record<string, JsonMap> = {};
for (const workload of workloadRows) {
  section(`Workload profile: ${workload.key} (${workload.textKind}, ${workload.inputBytes} bytes, lane=${workload.lane})`);
  const disabled = runScenario(false, workload);
  const enabled = runScenario(true, workload);
  workloads[workload.key] = {
    textKind: workload.textKind,
    lane: workload.lane,
    inputBytes: workload.inputBytes,
    description: workload.description,
    disabled,
    enabled,
    comparison: compareScenarios(disabled, enabled),
  };
}

const lowEntropy = isRecord(workloads.lowEntropy) ? (workloads.lowEntropy as JsonMap) : null;
const legacyDisabled = isRecord(lowEntropy?.["disabled"]) ? (lowEntropy["disabled"] as JsonMap) : null;
const legacyEnabled = isRecord(lowEntropy?.["enabled"]) ? (lowEntropy["enabled"] as JsonMap) : null;

writeJson(outputPath, {
  tool: "gpu-bpe-direct-bench",
  generatedAt: new Date().toISOString(),
  speedProfile,
  note: "A/B run for true on-GPU BPE direct merge route vs host-stitched path on low-entropy and normal-text profiles.",
  matrix: {
    directEnable: [false, true],
    textProfiles: workloadRows.map((row) => row.textKind),
    inputBytes: workloadRows.map((row) => row.inputBytes),
    lanes: workloadRows.map((row) => row.lane),
    selectedWorkloads: workloadRows.map((row) => row.key),
  },
  workloads,
  scenarios: {
    disabled: legacyDisabled,
    enabled: legacyEnabled,
  },
});

console.log(`Wrote GPU BPE direct A/B benchmark: ${outputPath}`);
