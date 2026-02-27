#!/usr/bin/env bun
import { readFileSync } from "node:fs";
import os from "node:os";
import { join } from "node:path";
import { readdirSync } from "node:fs";
import { resolvePath, runCommand, section, writeJson } from "./_lib";

type JsonMap = Record<string, unknown>;

type Mode = "all" | "cpu" | "gpu";

interface CpuGates {
  startupColdMaxMs: number;
  encode1mbMaxMs: number;
  count1mbMaxMs: number;
  training100kbNativeMaxMs: number;
  peakRssEncode1mbMaxMb: number;
  encode1mbMinMiBPerSec: number;
  count1mbMinMiBPerSec: number;
}

interface GpuGates {
  maxDeviceAllocatedMiB: number;
  minBpeDirectEncodeMiBPerSec: number;
  requireGpuMemoryRows: boolean;
}

interface GateConfig {
  version: number;
  cpu: CpuGates;
  gpu: GpuGates;
  relative?: RelativeGatesConfig;
  profiles?: Record<string, GateProfileOverride>;
}

interface GateFailure {
  metric: string;
  observed: number | null;
  expectation: string;
  artifact: string | null;
}

interface RelativeMaxGate {
  baseline: number;
  maxRegressionPct: number;
}

interface RelativeMinGate {
  baseline: number;
  maxDropPct: number;
}

interface CpuRelativeGates {
  startupColdMs?: RelativeMaxGate;
  encode1mbMs?: RelativeMaxGate;
  count1mbMs?: RelativeMaxGate;
  training100kbNativeMs?: RelativeMaxGate;
  peakRssEncode1mbMb?: RelativeMaxGate;
  encode1mbMiBPerSec?: RelativeMinGate;
  count1mbMiBPerSec?: RelativeMinGate;
}

interface GpuRelativeGates {
  maxDeviceAllocatedMiB?: RelativeMaxGate;
  directBpeEncodeMiBPerSec?: RelativeMinGate;
}

interface RelativeGatesConfig {
  enabled?: boolean;
  cpu?: CpuRelativeGates;
  gpu?: GpuRelativeGates;
}

interface GateProfileOverride {
  cpu?: Partial<CpuGates>;
  gpu?: Partial<GpuGates>;
  relative?: RelativeGatesConfig;
  host?: {
    platform?: string;
    arch?: string;
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function toNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function parseMode(argv: string[]): Mode {
  const modeArg = argv.find((arg) => arg.startsWith("--mode="));
  const value = modeArg ? modeArg.slice("--mode=".length).trim().toLowerCase() : "all";
  if (value === "cpu" || value === "gpu" || value === "all") {
    return value;
  }
  throw new Error(`invalid mode ${JSON.stringify(value)} (expected all|cpu|gpu)`);
}

function parseGatesPath(argv: string[]): string {
  const arg = argv.find((item) => item.startsWith("--gates="));
  if (!arg) {
    return resolvePath("bench", "ci-gates.json");
  }
  const raw = arg.slice("--gates=".length).trim();
  return raw.length > 0 ? resolvePath(raw) : resolvePath("bench", "ci-gates.json");
}

function parseProfileName(argv: string[]): string | null {
  const arg = argv.find((item) => item.startsWith("--profile="));
  if (arg) {
    const raw = arg.slice("--profile=".length).trim();
    return raw.length > 0 ? raw : null;
  }
  const env = (process.env.TURBOTOKEN_CI_GATES_PROFILE ?? "").trim();
  return env.length > 0 ? env : null;
}

function latestResultPath(prefix: string, options: { excludes?: string[] } = {}): string | null {
  const excludes = options.excludes ?? [];
  const resultsDir = resolvePath("bench", "results");
  const names = readdirSync(resultsDir)
    .filter(
      (name) =>
        name.startsWith(`${prefix}-`) &&
        name.endsWith(".json") &&
        !name.endsWith(".meta.json") &&
        excludes.every((needle) => !name.includes(needle)),
    )
    .sort();
  if (names.length === 0) {
    return null;
  }
  return join(resultsDir, names[names.length - 1]);
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

function commandMeanMs(payload: JsonMap | null, commandName: string): number | null {
  if (!payload) {
    return null;
  }
  const results = payload["results"];
  if (!Array.isArray(results)) {
    return null;
  }
  for (const row of results) {
    if (!isRecord(row)) {
      continue;
    }
    const rowName = row["command"] ?? row["commandName"];
    if (rowName !== commandName) {
      continue;
    }
    const meanSeconds = toNumber(row["mean"]) ?? toNumber(row["meanSeconds"]);
    return meanSeconds == null ? null : meanSeconds * 1000;
  }
  return null;
}

function findTrainingMeanMs(payload: JsonMap | null): number | null {
  if (!payload) {
    return null;
  }
  const results = payload["results"];
  if (!Array.isArray(results)) {
    return null;
  }
  const exact = commandMeanMs(payload, "python-train-english-100kb-turbotoken-native-v320");
  if (exact != null) {
    return exact;
  }
  for (const row of results) {
    if (!isRecord(row)) {
      continue;
    }
    const name = String(row["command"] ?? row["commandName"] ?? "");
    if (!name.includes("-turbotoken-native-v")) {
      continue;
    }
    const meanSeconds = toNumber(row["mean"]) ?? toNumber(row["meanSeconds"]);
    if (meanSeconds != null) {
      return meanSeconds * 1000;
    }
  }
  return null;
}

function parseRamMedianMb(payload: JsonMap | null, rowName: string): number | null {
  if (!payload) {
    return null;
  }
  const rows = payload["rows"];
  if (!Array.isArray(rows)) {
    return null;
  }
  for (const row of rows) {
    if (!isRecord(row)) {
      continue;
    }
    if (String(row["name"] ?? "") !== rowName) {
      continue;
    }
    const kb = toNumber(row["medianRssKb"]);
    return kb == null ? null : kb / 1024;
  }
  return null;
}

function parseGpuMemory(payload: JsonMap | null): {
  skippedReason: string | null;
  maxDeviceAllocatedMiB: number | null;
  bestBpeDirectMiBPerSec: number | null;
} {
  if (!payload) {
    return {
      skippedReason: "missing payload",
      maxDeviceAllocatedMiB: null,
      bestBpeDirectMiBPerSec: null,
    };
  }

  const status = String(payload["status"] ?? "ok");
  if (status !== "ok") {
    return {
      skippedReason: String(payload["reason"] ?? payload["status"] ?? "gpu benchmark skipped"),
      maxDeviceAllocatedMiB: null,
      bestBpeDirectMiBPerSec: null,
    };
  }

  const rows = payload["rows"];
  if (!Array.isArray(rows)) {
    return {
      skippedReason: "rows missing",
      maxDeviceAllocatedMiB: null,
      bestBpeDirectMiBPerSec: null,
    };
  }

  let maxDeviceAllocatedMiB: number | null = null;
  let bestBpeDirectMiBPerSec: number | null = null;

  for (const row of rows) {
    if (!isRecord(row)) {
      continue;
    }
    const rowMax = toNumber(row["max_device_allocated_mib"]);
    if (rowMax != null) {
      maxDeviceAllocatedMiB = maxDeviceAllocatedMiB == null ? rowMax : Math.max(maxDeviceAllocatedMiB, rowMax);
    }

    const name = String(row["name"] ?? "");
    const throughput = toNumber(row["median_gpu_mib_per_s"]);
    if (name === "metal-bpe-direct-encode-1mb" && throughput != null) {
      bestBpeDirectMiBPerSec = throughput;
    }
  }

  return {
    skippedReason: null,
    maxDeviceAllocatedMiB,
    bestBpeDirectMiBPerSec,
  };
}

function mibPerSecFromMs(totalMiB: number, ms: number | null): number | null {
  if (ms == null || ms <= 0) {
    return null;
  }
  return (totalMiB * 1000) / ms;
}

function addMaxGate(
  failures: GateFailure[],
  metric: string,
  observed: number | null,
  maxAllowed: number,
  artifact: string | null,
): void {
  if (observed == null || observed > maxAllowed) {
    failures.push({
      metric,
      observed,
      expectation: `<= ${maxAllowed}`,
      artifact,
    });
  }
}

function addMinGate(
  failures: GateFailure[],
  metric: string,
  observed: number | null,
  minAllowed: number,
  artifact: string | null,
): void {
  if (observed == null || observed < minAllowed) {
    failures.push({
      metric,
      observed,
      expectation: `>= ${minAllowed}`,
      artifact,
    });
  }
}

function addRelativeMaxGate(
  failures: GateFailure[],
  metric: string,
  observed: number | null,
  gate: RelativeMaxGate | undefined,
  artifact: string | null,
): void {
  if (!gate) {
    return;
  }
  if (!Number.isFinite(gate.baseline) || gate.baseline < 0) {
    throw new Error(`invalid relative max gate baseline for ${metric}`);
  }
  if (!Number.isFinite(gate.maxRegressionPct) || gate.maxRegressionPct < 0) {
    throw new Error(`invalid relative max gate regression pct for ${metric}`);
  }
  const maxAllowed = gate.baseline * (1 + gate.maxRegressionPct / 100);
  if (observed == null || observed > maxAllowed) {
    failures.push({
      metric: `${metric} (relative)`,
      observed,
      expectation: `<= ${maxAllowed} (${gate.maxRegressionPct}% over baseline ${gate.baseline})`,
      artifact,
    });
  }
}

function addRelativeMinGate(
  failures: GateFailure[],
  metric: string,
  observed: number | null,
  gate: RelativeMinGate | undefined,
  artifact: string | null,
): void {
  if (!gate) {
    return;
  }
  if (!Number.isFinite(gate.baseline) || gate.baseline <= 0) {
    throw new Error(`invalid relative min gate baseline for ${metric}`);
  }
  if (!Number.isFinite(gate.maxDropPct) || gate.maxDropPct < 0 || gate.maxDropPct >= 100) {
    throw new Error(`invalid relative min gate drop pct for ${metric}`);
  }
  const minAllowed = gate.baseline * (1 - gate.maxDropPct / 100);
  if (observed == null || observed < minAllowed) {
    failures.push({
      metric: `${metric} (relative)`,
      observed,
      expectation: `>= ${minAllowed} (${gate.maxDropPct}% below baseline ${gate.baseline})`,
      artifact,
    });
  }
}

function mergeRelativeGates(
  base: RelativeGatesConfig | undefined,
  override: RelativeGatesConfig | undefined,
): RelativeGatesConfig | undefined {
  if (!base && !override) {
    return undefined;
  }
  const merged: RelativeGatesConfig = {};
  if (base) {
    merged.enabled = base.enabled;
    merged.cpu = base.cpu ? { ...base.cpu } : undefined;
    merged.gpu = base.gpu ? { ...base.gpu } : undefined;
  }
  if (override) {
    if (override.enabled !== undefined) {
      merged.enabled = override.enabled;
    }
    if (override.cpu) {
      merged.cpu = {
        ...(merged.cpu ?? {}),
        ...override.cpu,
      };
    }
    if (override.gpu) {
      merged.gpu = {
        ...(merged.gpu ?? {}),
        ...override.gpu,
      };
    }
  }
  return merged;
}

function applyProfile(base: GateConfig, profileName: string | null): {
  effective: GateConfig;
  selectedProfile: string | null;
} {
  if (!profileName) {
    return { effective: base, selectedProfile: null };
  }
  const profiles = base.profiles;
  if (!isRecord(profiles)) {
    throw new Error(`gate profile ${JSON.stringify(profileName)} requested but no profiles are defined`);
  }
  const rawOverride = profiles[profileName];
  if (!isRecord(rawOverride)) {
    const available = Object.keys(profiles).sort();
    throw new Error(
      `gate profile ${JSON.stringify(profileName)} not found; available profiles: ${available.join(", ")}`,
    );
  }
  const override = rawOverride as GateProfileOverride;
  const effective: GateConfig = {
    ...base,
    cpu: {
      ...base.cpu,
      ...(override.cpu ?? {}),
    },
    gpu: {
      ...base.gpu,
      ...(override.gpu ?? {}),
    },
    relative: mergeRelativeGates(base.relative, override.relative),
  };
  return { effective, selectedProfile: profileName };
}

function runScripts(mode: Mode): void {
  const cpuScripts = [
    "scripts/generate-fixture.ts",
    "scripts/bench-startup.ts",
    "scripts/bench-competitors.ts",
    "scripts/bench-training.ts",
    "scripts/bench-ram.ts",
  ];

  const gpuScripts = [
    "scripts/generate-fixture.ts",
    "scripts/bench-gpu-memory.ts",
    "scripts/bench-gpu-crossover.ts",
    "scripts/bench-gpu-overlap.ts",
  ];

  let scripts: string[];
  if (mode === "cpu") {
    scripts = cpuScripts;
  } else if (mode === "gpu") {
    scripts = gpuScripts;
  } else {
    scripts = [...new Set([...cpuScripts, ...gpuScripts])];
  }

  for (const script of scripts) {
    section(`CI benchmark: ${script}`);
    const result = runCommand("bun", ["run", script], { allowFailure: true });
    if (result.stdout.trim().length > 0) {
      console.log(result.stdout.trim());
    }
    if (result.stderr.trim().length > 0) {
      console.error(result.stderr.trim());
    }
    if (result.code !== 0) {
      throw new Error(`${script} failed with exit code ${result.code}`);
    }
  }
}

const mode = parseMode(process.argv.slice(2));
const gatesPath = parseGatesPath(process.argv.slice(2));
const profileName = parseProfileName(process.argv.slice(2));
const noRun = process.argv.includes("--no-run");
const includeCuda = ["1", "true", "yes", "on"].includes(
  (process.env.TURBOTOKEN_BENCH_INCLUDE_CUDA ?? "").trim().toLowerCase(),
);

if (includeCuda) {
  console.warn("CI benchmark gates intentionally exclude CUDA by default; CUDA remains on-demand only.");
}

if (!noRun) {
  runScripts(mode);
}

const parsedGates = JSON.parse(readFileSync(gatesPath, "utf8")) as GateConfig;
if (!isRecord(parsedGates) || !isRecord(parsedGates.cpu) || !isRecord(parsedGates.gpu)) {
  throw new Error(`invalid gates config: ${gatesPath}`);
}
const { effective: gates, selectedProfile } = applyProfile(parsedGates, profileName);
const relativeEnabled = gates.relative?.enabled === true;

const artifacts = {
  startupCold: latestResultPath("bench-startup-cold"),
  competitorsEncode: latestResultPath("bench-competitors-python-encode"),
  competitorsCount: latestResultPath("bench-competitors-python-count"),
  training: latestResultPath("bench-training-python"),
  ram: latestResultPath("bench-ram"),
  gpuMemory: latestResultPath("bench-gpu-memory", { excludes: ["-cuda-"] }),
  gpuOverlap: latestResultPath("bench-gpu-overlap"),
};

const startupCold = loadJson(artifacts.startupCold);
const competitorsEncode = loadJson(artifacts.competitorsEncode);
const competitorsCount = loadJson(artifacts.competitorsCount);
const training = loadJson(artifacts.training);
const ram = loadJson(artifacts.ram);
const gpuMemory = loadJson(artifacts.gpuMemory);

const startupColdMs = commandMeanMs(startupCold, "python-startup-turbotoken");
const encode1mbMs = commandMeanMs(competitorsEncode, "python-encode-1mb-turbotoken");
const count1mbMs = commandMeanMs(competitorsCount, "python-count-1mb-turbotoken");
const training100kbNativeMs = findTrainingMeanMs(training);
const peakRssEncode1mbMb = parseRamMedianMb(ram, "python-ram-turbotoken-encode-1mb");
const encode1mbMiBPerSec = mibPerSecFromMs(1.0, encode1mbMs);
const count1mbMiBPerSec = mibPerSecFromMs(1.0, count1mbMs);

const gpuParsed = parseGpuMemory(gpuMemory);

const failures: GateFailure[] = [];
if (mode === "all" || mode === "cpu") {
  addMaxGate(
    failures,
    "startup cold ms",
    startupColdMs,
    gates.cpu.startupColdMaxMs,
    artifacts.startupCold,
  );
  addMaxGate(
    failures,
    "encode 1mb ms",
    encode1mbMs,
    gates.cpu.encode1mbMaxMs,
    artifacts.competitorsEncode,
  );
  addMaxGate(
    failures,
    "count 1mb ms",
    count1mbMs,
    gates.cpu.count1mbMaxMs,
    artifacts.competitorsCount,
  );
  addMaxGate(
    failures,
    "training 100kb native ms",
    training100kbNativeMs,
    gates.cpu.training100kbNativeMaxMs,
    artifacts.training,
  );
  addMaxGate(
    failures,
    "peak RSS encode 1mb MB",
    peakRssEncode1mbMb,
    gates.cpu.peakRssEncode1mbMaxMb,
    artifacts.ram,
  );
  addMinGate(
    failures,
    "encode 1mb MiB/s",
    encode1mbMiBPerSec,
    gates.cpu.encode1mbMinMiBPerSec,
    artifacts.competitorsEncode,
  );
  addMinGate(
    failures,
    "count 1mb MiB/s",
    count1mbMiBPerSec,
    gates.cpu.count1mbMinMiBPerSec,
    artifacts.competitorsCount,
  );
  if (relativeEnabled) {
    const cpuRelative = gates.relative?.cpu;
    addRelativeMaxGate(
      failures,
      "startup cold ms",
      startupColdMs,
      cpuRelative?.startupColdMs,
      artifacts.startupCold,
    );
    addRelativeMaxGate(
      failures,
      "encode 1mb ms",
      encode1mbMs,
      cpuRelative?.encode1mbMs,
      artifacts.competitorsEncode,
    );
    addRelativeMaxGate(
      failures,
      "count 1mb ms",
      count1mbMs,
      cpuRelative?.count1mbMs,
      artifacts.competitorsCount,
    );
    addRelativeMaxGate(
      failures,
      "training 100kb native ms",
      training100kbNativeMs,
      cpuRelative?.training100kbNativeMs,
      artifacts.training,
    );
    addRelativeMaxGate(
      failures,
      "peak RSS encode 1mb MB",
      peakRssEncode1mbMb,
      cpuRelative?.peakRssEncode1mbMb,
      artifacts.ram,
    );
    addRelativeMinGate(
      failures,
      "encode 1mb MiB/s",
      encode1mbMiBPerSec,
      cpuRelative?.encode1mbMiBPerSec,
      artifacts.competitorsEncode,
    );
    addRelativeMinGate(
      failures,
      "count 1mb MiB/s",
      count1mbMiBPerSec,
      cpuRelative?.count1mbMiBPerSec,
      artifacts.competitorsCount,
    );
  }
}

if (mode === "all" || mode === "gpu") {
  if (gpuParsed.skippedReason != null) {
    if (gates.gpu.requireGpuMemoryRows) {
      failures.push({
        metric: "gpu memory rows",
        observed: null,
        expectation: "GPU rows required",
        artifact: artifacts.gpuMemory,
      });
    }
  } else {
    addMaxGate(
      failures,
      "gpu max device allocated MiB",
      gpuParsed.maxDeviceAllocatedMiB,
      gates.gpu.maxDeviceAllocatedMiB,
      artifacts.gpuMemory,
    );
    addMinGate(
      failures,
      "gpu direct bpe encode MiB/s",
      gpuParsed.bestBpeDirectMiBPerSec,
      gates.gpu.minBpeDirectEncodeMiBPerSec,
      artifacts.gpuMemory,
    );
    if (relativeEnabled) {
      const gpuRelative = gates.relative?.gpu;
      addRelativeMaxGate(
        failures,
        "gpu max device allocated MiB",
        gpuParsed.maxDeviceAllocatedMiB,
        gpuRelative?.maxDeviceAllocatedMiB,
        artifacts.gpuMemory,
      );
      addRelativeMinGate(
        failures,
        "gpu direct bpe encode MiB/s",
        gpuParsed.bestBpeDirectMiBPerSec,
        gpuRelative?.directBpeEncodeMiBPerSec,
        artifacts.gpuMemory,
      );
    }
  }
}

const summary = {
  mode,
  cudaDefaultOff: !includeCuda,
  selectedProfile,
  relativeEnabled,
  host: {
    platform: process.platform,
    arch: process.arch,
    release: os.release(),
    hostname: os.hostname(),
  },
  gatesPath,
  artifacts,
  metrics: {
    startupColdMs,
    encode1mbMs,
    count1mbMs,
    training100kbNativeMs,
    peakRssEncode1mbMb,
    encode1mbMiBPerSec,
    count1mbMiBPerSec,
    gpuMemory: gpuParsed,
  },
  failures,
};

const profileTag = selectedProfile ? selectedProfile.replace(/[^a-zA-Z0-9_-]+/g, "_") : "default";
const outPath = resolvePath(
  "bench",
  "results",
  `ci-benchmark-${mode}-${profileTag}-${Date.now()}-${process.pid}.json`,
);
writeJson(outPath, summary);
console.log(`Wrote CI benchmark summary: ${outPath}`);

if (failures.length > 0) {
  console.error(`CI benchmark gates failed (${failures.length}):`);
  for (const failure of failures) {
    console.error(
      `- ${failure.metric}: observed=${failure.observed == null ? "n/a" : failure.observed} expected ${failure.expectation} (${failure.artifact ?? "artifact missing"})`,
    );
  }
  process.exit(1);
}

console.log("CI benchmark gates passed.");
