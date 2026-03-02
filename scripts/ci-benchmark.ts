#!/usr/bin/env bun
import { existsSync, readFileSync } from "node:fs";
import os from "node:os";
import { join } from "node:path";
import { readdirSync } from "node:fs";
import { acquireBenchmarkLock, resolvePath, runCommand, section, writeJson } from "./_lib";

type JsonMap = Record<string, unknown>;

acquireBenchmarkLock({ label: "ci-benchmark" });

type Mode = "all" | "cpu" | "gpu";

interface CpuGates {
  startupColdMaxMs: number;
  encode1mbMaxMs: number;
  count1mbMaxMs: number;
  training100kbNativeMaxMs: number;
  requireTrainingCompetitorRows?: boolean;
  training100kbNativeMaxRustbpeRatio?: number;
  training100kbNativeMaxMinbpeRatio?: number;
  peakRssEncode1mbMaxMb: number;
  encode1mbMinMiBPerSec: number;
  count1mbMinMiBPerSec: number;
}

interface GpuGates {
  maxDeviceAllocatedMiB: number;
  minBpeDirectEncodeMiBPerSec: number;
  requireGpuMemoryRows: boolean;
  requireDirect1mbParity?: boolean;
  directAbSafety?: DirectAbSafetyGates;
}

interface DirectAbSafetyGates {
  requireRows: boolean;
  lowEntropyMaxSlowdownPct: number;
  lowEntropyMinThroughputRatio: number;
  normalTextMaxSlowdownPct: number;
  normalTextMinThroughputRatio: number;
  requireLowEntropyNoDirectRoute: boolean;
  requireNormalTextDirectRoute: boolean;
  requireTokenParity: boolean;
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

interface GpuDirectAbWorkload {
  textKind: string;
  slowdownPct: number | null;
  throughputRatio: number | null;
  disabledMatchesBaseline: boolean | null;
  enabledMatchesBaseline: boolean | null;
  disabledUsedDirectRoute: boolean | null;
  enabledUsedDirectRoute: boolean | null;
}

interface GpuDirectAbParsed {
  skippedReason: string | null;
  lowEntropy: GpuDirectAbWorkload | null;
  normalText: GpuDirectAbWorkload | null;
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

function normalizeSpeedProfile(raw: string | null): "fast" | "full" | null {
  if (!raw) {
    return null;
  }
  const lowered = raw.trim().toLowerCase();
  if (lowered === "fast" || lowered === "quick") {
    return "fast";
  }
  if (lowered === "full") {
    return "full";
  }
  if (lowered === "any" || lowered === "*") {
    return null;
  }
  throw new Error(`invalid artifact speed profile ${JSON.stringify(raw)} (expected full|fast|any)`);
}

function parseArtifactSpeedProfile(argv: string[], noRun: boolean): "fast" | "full" | null {
  const arg = argv.find((item) => item.startsWith("--artifact-speed="));
  if (arg) {
    return normalizeSpeedProfile(arg.slice("--artifact-speed=".length));
  }
  if (noRun) {
    // Gate-only checks should default to full-fidelity artifacts unless explicitly overridden.
    return "full";
  }
  const env = process.env.TURBOTOKEN_CI_ARTIFACT_SPEED ?? "full";
  return normalizeSpeedProfile(env);
}

function artifactMetaPath(path: string): string {
  if (path.endsWith(".json")) {
    return `${path.slice(0, -5)}.meta.json`;
  }
  return `${path}.meta.json`;
}

function artifactSpeedProfile(path: string, payload: JsonMap | null): "fast" | "full" | null {
  const fromPayload = normalizeSpeedProfile(
    typeof payload?.["speedProfile"] === "string" ? String(payload["speedProfile"]) : null,
  );
  if (fromPayload != null) {
    return fromPayload;
  }

  const benchmark = payload?.["benchmark"];
  if (isRecord(benchmark)) {
    const fromBenchmark = normalizeSpeedProfile(
      typeof benchmark["speedProfile"] === "string" ? String(benchmark["speedProfile"]) : null,
    );
    if (fromBenchmark != null) {
      return fromBenchmark;
    }
  }

  const metaPath = artifactMetaPath(path);
  if (!existsSync(metaPath)) {
    return null;
  }
  try {
    const meta = JSON.parse(readFileSync(metaPath, "utf8")) as JsonMap;
    const fromMeta = normalizeSpeedProfile(
      typeof meta["speedProfile"] === "string" ? String(meta["speedProfile"]) : null,
    );
    if (fromMeta != null) {
      return fromMeta;
    }
    const tuning = meta["benchmarkTuning"];
    if (isRecord(tuning)) {
      return normalizeSpeedProfile(
        typeof tuning["speedProfile"] === "string" ? String(tuning["speedProfile"]) : null,
      );
    }
  } catch {
    return null;
  }
  return null;
}

function latestResultPath(
  prefix: string,
  options: { excludes?: string[]; speedProfile?: "fast" | "full" | null } = {},
): string | null {
  const excludes = options.excludes ?? [];
  const desiredSpeed = options.speedProfile ?? null;
  const resultsDir = resolvePath("bench", "results");
  const names = readdirSync(resultsDir)
    .filter(
      (name) =>
        name.startsWith(`${prefix}-`) &&
        name.endsWith(".json") &&
        !name.endsWith(".meta.json") &&
        excludes.every((needle) => !name.includes(needle)),
    )
    .sort()
    .reverse();
  for (const name of names) {
    const path = join(resultsDir, name);
    const payload = loadJson(path);
    if (desiredSpeed != null) {
      const observed = artifactSpeedProfile(path, payload);
      if (observed !== desiredSpeed) {
        continue;
      }
    }
    return path;
  }
  return null;
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

function latestResultPathMatching(
  prefix: string,
  matcher: (payload: JsonMap) => boolean,
  options: { excludes?: string[]; speedProfile?: "fast" | "full" | null } = {},
): string | null {
  const excludes = options.excludes ?? [];
  const desiredSpeed = options.speedProfile ?? null;
  const resultsDir = resolvePath("bench", "results");
  const names = readdirSync(resultsDir)
    .filter(
      (name) =>
        name.startsWith(`${prefix}-`) &&
        name.endsWith(".json") &&
        !name.endsWith(".meta.json") &&
        excludes.every((needle) => !name.includes(needle)),
    )
    .sort()
    .reverse();
  for (const name of names) {
    const path = join(resultsDir, name);
    const payload = loadJson(path);
    if (payload) {
      if (desiredSpeed != null) {
        const observed = artifactSpeedProfile(path, payload);
        if (observed !== desiredSpeed) {
          continue;
        }
      }
      if (!matcher(payload)) {
        continue;
      }
      return path;
    }
  }
  return null;
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

function findTrainingCompetitorMeanMs(payload: JsonMap | null, competitor: "rustbpe" | "minbpe"): number | null {
  if (!payload) {
    return null;
  }
  const results = payload["results"];
  if (!Array.isArray(results)) {
    return null;
  }
  const strictNeedle = `-english-100kb-${competitor}-v`;
  const looseNeedle = `-${competitor}-v`;
  for (const row of results) {
    if (!isRecord(row)) {
      continue;
    }
    const name = String(row["command"] ?? row["commandName"] ?? "");
    if (!name.includes(strictNeedle) && !name.includes(looseNeedle)) {
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
  direct1mbMatchesNative: boolean | null;
} {
  if (!payload) {
    return {
      skippedReason: "missing payload",
      maxDeviceAllocatedMiB: null,
      bestBpeDirectMiBPerSec: null,
      direct1mbMatchesNative: null,
    };
  }

  const status = String(payload["status"] ?? "ok");
  if (status !== "ok") {
    return {
      skippedReason: String(payload["reason"] ?? payload["status"] ?? "gpu benchmark skipped"),
      maxDeviceAllocatedMiB: null,
      bestBpeDirectMiBPerSec: null,
      direct1mbMatchesNative: null,
    };
  }

  const rows = payload["rows"];
  if (!Array.isArray(rows)) {
    return {
      skippedReason: "rows missing",
      maxDeviceAllocatedMiB: null,
      bestBpeDirectMiBPerSec: null,
      direct1mbMatchesNative: null,
    };
  }

  let maxDeviceAllocatedMiB: number | null = null;
  let bestBpeDirectMiBPerSec: number | null = null;
  let direct1mbMatchesNative: boolean | null = null;

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
      if (typeof row["matches_native"] === "boolean") {
        direct1mbMatchesNative = row["matches_native"] as boolean;
      }
    }
  }

  return {
    skippedReason: null,
    maxDeviceAllocatedMiB,
    bestBpeDirectMiBPerSec,
    direct1mbMatchesNative,
  };
}

function hasDirectGpuMemoryRow(payload: JsonMap): boolean {
  const rows = payload["rows"];
  if (!Array.isArray(rows)) {
    return false;
  }
  for (const row of rows) {
    if (!isRecord(row)) {
      continue;
    }
    if (String(row["name"] ?? "") !== "metal-bpe-direct-encode-1mb") {
      continue;
    }
    if (toNumber(row["median_gpu_mib_per_s"]) != null) {
      return true;
    }
  }
  return false;
}

function parseDirectScenario(value: unknown): {
  metalMs: number | null;
  metalMiBPerSec: number | null;
  matchesBaseline: boolean | null;
  usedDirectRoute: boolean | null;
} {
  if (!isRecord(value)) {
    return {
      metalMs: null,
      metalMiBPerSec: null,
      matchesBaseline: null,
      usedDirectRoute: null,
    };
  }
  const crossover = isRecord(value["crossover"]) ? (value["crossover"] as JsonMap) : null;
  const gpuMemory = isRecord(value["gpuMemory"]) ? (value["gpuMemory"] as JsonMap) : null;
  const route = isRecord(gpuMemory?.["route"]) ? (gpuMemory["route"] as JsonMap) : null;
  const routeKinds = parseRouteKindCounts(route?.["routeKindCounts"]);
  return {
    metalMs: toNumber(crossover?.["metalMs"]),
    metalMiBPerSec: toNumber(crossover?.["metalMiBPerSec"]),
    matchesBaseline:
      crossover && typeof crossover["metalMatchesBaseline"] === "boolean"
        ? (crossover["metalMatchesBaseline"] as boolean)
        : null,
    usedDirectRoute: route ? Object.prototype.hasOwnProperty.call(routeKinds, "direct") : null,
  };
}

function parseDirectWorkload(
  disabledValue: unknown,
  enabledValue: unknown,
  textKind: string,
): GpuDirectAbWorkload | null {
  const disabled = parseDirectScenario(disabledValue);
  const enabled = parseDirectScenario(enabledValue);
  const hasAnySignal =
    disabled.metalMs != null ||
    enabled.metalMs != null ||
    disabled.metalMiBPerSec != null ||
    enabled.metalMiBPerSec != null;
  if (!hasAnySignal) {
    return null;
  }
  return {
    textKind,
    slowdownPct: percentIncrease(disabled.metalMs, enabled.metalMs),
    throughputRatio: ratio(disabled.metalMiBPerSec, enabled.metalMiBPerSec),
    disabledMatchesBaseline: disabled.matchesBaseline,
    enabledMatchesBaseline: enabled.matchesBaseline,
    disabledUsedDirectRoute: disabled.usedDirectRoute,
    enabledUsedDirectRoute: enabled.usedDirectRoute,
  };
}

function parseGpuDirectAb(payload: JsonMap | null): GpuDirectAbParsed {
  if (!payload) {
    return {
      skippedReason: "missing payload",
      lowEntropy: null,
      normalText: null,
    };
  }

  const workloads = payload["workloads"];
  if (isRecord(workloads)) {
    const lowEntry = isRecord(workloads["lowEntropy"]) ? (workloads["lowEntropy"] as JsonMap) : null;
    const normalEntry = isRecord(workloads["normalText"]) ? (workloads["normalText"] as JsonMap) : null;

    const lowEntropy = parseDirectWorkload(lowEntry?.["disabled"], lowEntry?.["enabled"], "low-entropy");
    const normalText = parseDirectWorkload(normalEntry?.["disabled"], normalEntry?.["enabled"], "normal-text");
    const hasRows = lowEntropy != null || normalText != null;

    return {
      skippedReason: hasRows ? null : "workload rows missing",
      lowEntropy,
      normalText,
    };
  }

  const scenarios = payload["scenarios"];
  if (!isRecord(scenarios)) {
    return {
      skippedReason: "direct A/B scenarios missing",
      lowEntropy: null,
      normalText: null,
    };
  }
  const legacyLowEntropy = parseDirectWorkload(scenarios["disabled"], scenarios["enabled"], "low-entropy");
  return {
    skippedReason: legacyLowEntropy ? null : "legacy direct A/B rows missing",
    lowEntropy: legacyLowEntropy,
    normalText: null,
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

function addBooleanGate(
  failures: GateFailure[],
  metric: string,
  observed: boolean | null,
  expected: boolean,
  artifact: string | null,
): void {
  if (observed === expected) {
    return;
  }
  failures.push({
    metric,
    observed: observed == null ? null : observed ? 1 : 0,
    expectation: expected ? "== true" : "== false",
    artifact,
  });
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

function runScripts(mode: Mode, benchmarkSpeed: "fast" | "full" | null): void {
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
    "scripts/bench-gpu-bpe-direct.ts",
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
    const benchEnv: Record<string, string> = {};
    if (benchmarkSpeed != null) {
      benchEnv.TURBOTOKEN_BENCH_SPEED = benchmarkSpeed;
      benchEnv.TURBOTOKEN_BENCH_FAST = benchmarkSpeed === "fast" ? "1" : "0";
    }
    const result = runCommand("bun", ["run", script], { allowFailure: true, env: benchEnv });
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
const artifactSpeed = parseArtifactSpeedProfile(process.argv.slice(2), noRun);
const includeCuda = ["1", "true", "yes", "on"].includes(
  (process.env.TURBOTOKEN_BENCH_INCLUDE_CUDA ?? "").trim().toLowerCase(),
);

if (includeCuda) {
  console.warn("CI benchmark gates intentionally exclude CUDA by default; CUDA remains on-demand only.");
}

if (!noRun) {
  runScripts(mode, artifactSpeed);
}

const parsedGates = JSON.parse(readFileSync(gatesPath, "utf8")) as GateConfig;
if (!isRecord(parsedGates) || !isRecord(parsedGates.cpu) || !isRecord(parsedGates.gpu)) {
  throw new Error(`invalid gates config: ${gatesPath}`);
}
const { effective: gates, selectedProfile } = applyProfile(parsedGates, profileName);
const relativeEnabled = gates.relative?.enabled === true;

const artifacts = {
  startupCold: latestResultPath("bench-startup-cold", { speedProfile: artifactSpeed }),
  competitorsEncode: latestResultPath("bench-competitors-python-encode", { speedProfile: artifactSpeed }),
  competitorsCount: latestResultPath("bench-competitors-python-count", { speedProfile: artifactSpeed }),
  training: latestResultPath("bench-training-python", { speedProfile: artifactSpeed }),
  ram: latestResultPath("bench-ram", { speedProfile: artifactSpeed }),
  gpuMemory:
    latestResultPathMatching("bench-gpu-memory", hasDirectGpuMemoryRow, {
      excludes: ["-cuda-"],
      speedProfile: artifactSpeed,
    }) ??
    latestResultPath("bench-gpu-memory", { excludes: ["-cuda-"], speedProfile: artifactSpeed }),
  gpuBpeDirect: latestResultPath("bench-gpu-bpe-direct", { speedProfile: artifactSpeed }),
  gpuOverlap: latestResultPath("bench-gpu-overlap", { speedProfile: artifactSpeed }),
};

const startupCold = loadJson(artifacts.startupCold);
const competitorsEncode = loadJson(artifacts.competitorsEncode);
const competitorsCount = loadJson(artifacts.competitorsCount);
const training = loadJson(artifacts.training);
const ram = loadJson(artifacts.ram);
const gpuMemory = loadJson(artifacts.gpuMemory);
const gpuBpeDirect = loadJson(artifacts.gpuBpeDirect);

const artifactSpeeds = {
  startupCold: artifactSpeedProfile(artifacts.startupCold ?? "", startupCold),
  competitorsEncode: artifactSpeedProfile(artifacts.competitorsEncode ?? "", competitorsEncode),
  competitorsCount: artifactSpeedProfile(artifacts.competitorsCount ?? "", competitorsCount),
  training: artifactSpeedProfile(artifacts.training ?? "", training),
  ram: artifactSpeedProfile(artifacts.ram ?? "", ram),
  gpuMemory: artifactSpeedProfile(artifacts.gpuMemory ?? "", gpuMemory),
  gpuBpeDirect: artifactSpeedProfile(artifacts.gpuBpeDirect ?? "", gpuBpeDirect),
  gpuOverlap: artifactSpeedProfile(artifacts.gpuOverlap ?? "", loadJson(artifacts.gpuOverlap)),
};

const startupColdMs = commandMeanMs(startupCold, "python-startup-turbotoken");
const encode1mbMs = commandMeanMs(competitorsEncode, "python-encode-1mb-turbotoken");
const count1mbMs = commandMeanMs(competitorsCount, "python-count-1mb-turbotoken");
const training100kbNativeMs = findTrainingMeanMs(training);
const training100kbRustbpeMs = findTrainingCompetitorMeanMs(training, "rustbpe");
const training100kbMinbpeMs = findTrainingCompetitorMeanMs(training, "minbpe");
const training100kbNativeVsRustbpeRatio =
  training100kbNativeMs != null && training100kbRustbpeMs != null && training100kbRustbpeMs > 0
    ? training100kbNativeMs / training100kbRustbpeMs
    : null;
const training100kbNativeVsMinbpeRatio =
  training100kbNativeMs != null && training100kbMinbpeMs != null && training100kbMinbpeMs > 0
    ? training100kbNativeMs / training100kbMinbpeMs
    : null;
const peakRssEncode1mbMb = parseRamMedianMb(ram, "python-ram-turbotoken-encode-1mb");
const encode1mbMiBPerSec = mibPerSecFromMs(1.0, encode1mbMs);
const count1mbMiBPerSec = mibPerSecFromMs(1.0, count1mbMs);

const gpuParsed = parseGpuMemory(gpuMemory);
const gpuDirectAb = parseGpuDirectAb(gpuBpeDirect);

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
  if (gates.cpu.requireTrainingCompetitorRows === true) {
    addBooleanGate(
      failures,
      "training 100kb rustbpe row present",
      training100kbRustbpeMs != null,
      true,
      artifacts.training,
    );
    addBooleanGate(
      failures,
      "training 100kb minbpe row present",
      training100kbMinbpeMs != null,
      true,
      artifacts.training,
    );
  }
  if (gates.cpu.training100kbNativeMaxRustbpeRatio != null) {
    addMaxGate(
      failures,
      "training 100kb native vs rustbpe ratio",
      training100kbNativeVsRustbpeRatio,
      gates.cpu.training100kbNativeMaxRustbpeRatio,
      artifacts.training,
    );
  }
  if (gates.cpu.training100kbNativeMaxMinbpeRatio != null) {
    addMaxGate(
      failures,
      "training 100kb native vs minbpe ratio",
      training100kbNativeVsMinbpeRatio,
      gates.cpu.training100kbNativeMaxMinbpeRatio,
      artifacts.training,
    );
  }
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
    if (gates.gpu.requireDirect1mbParity === true) {
      addBooleanGate(
        failures,
        "gpu direct 1mb parity",
        gpuParsed.direct1mbMatchesNative,
        true,
        artifacts.gpuMemory,
      );
    }
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

  const directSafety = gates.gpu.directAbSafety;
  if (directSafety) {
    if (gpuDirectAb.skippedReason != null) {
      if (directSafety.requireRows) {
        failures.push({
          metric: "gpu direct A/B rows",
          observed: null,
          expectation: `required (${gpuDirectAb.skippedReason})`,
          artifact: artifacts.gpuBpeDirect,
        });
      }
    } else {
      const lowEntropy = gpuDirectAb.lowEntropy;
      if (!lowEntropy) {
        if (directSafety.requireRows) {
          failures.push({
            metric: "gpu direct A/B low-entropy rows",
            observed: null,
            expectation: "required",
            artifact: artifacts.gpuBpeDirect,
          });
        }
      } else {
        addMaxGate(
          failures,
          "gpu direct A/B low-entropy slowdown pct",
          lowEntropy.slowdownPct,
          directSafety.lowEntropyMaxSlowdownPct,
          artifacts.gpuBpeDirect,
        );
        addMinGate(
          failures,
          "gpu direct A/B low-entropy throughput ratio",
          lowEntropy.throughputRatio,
          directSafety.lowEntropyMinThroughputRatio,
          artifacts.gpuBpeDirect,
        );
        if (directSafety.requireTokenParity) {
          addBooleanGate(
            failures,
            "gpu direct A/B low-entropy disabled parity",
            lowEntropy.disabledMatchesBaseline,
            true,
            artifacts.gpuBpeDirect,
          );
          addBooleanGate(
            failures,
            "gpu direct A/B low-entropy enabled parity",
            lowEntropy.enabledMatchesBaseline,
            true,
            artifacts.gpuBpeDirect,
          );
        }
        if (directSafety.requireLowEntropyNoDirectRoute) {
          addBooleanGate(
            failures,
            "gpu direct A/B low-entropy enabled direct-route disabled",
            lowEntropy.enabledUsedDirectRoute,
            false,
            artifacts.gpuBpeDirect,
          );
        }
      }

      const normalText = gpuDirectAb.normalText;
      if (!normalText) {
        if (directSafety.requireRows) {
          failures.push({
            metric: "gpu direct A/B normal-text rows",
            observed: null,
            expectation: "required",
            artifact: artifacts.gpuBpeDirect,
          });
        }
      } else {
        addMaxGate(
          failures,
          "gpu direct A/B normal-text slowdown pct",
          normalText.slowdownPct,
          directSafety.normalTextMaxSlowdownPct,
          artifacts.gpuBpeDirect,
        );
        addMinGate(
          failures,
          "gpu direct A/B normal-text throughput ratio",
          normalText.throughputRatio,
          directSafety.normalTextMinThroughputRatio,
          artifacts.gpuBpeDirect,
        );
        if (directSafety.requireTokenParity) {
          addBooleanGate(
            failures,
            "gpu direct A/B normal-text disabled parity",
            normalText.disabledMatchesBaseline,
            true,
            artifacts.gpuBpeDirect,
          );
          addBooleanGate(
            failures,
            "gpu direct A/B normal-text enabled parity",
            normalText.enabledMatchesBaseline,
            true,
            artifacts.gpuBpeDirect,
          );
        }
        if (directSafety.requireNormalTextDirectRoute) {
          addBooleanGate(
            failures,
            "gpu direct A/B normal-text enabled direct-route required",
            normalText.enabledUsedDirectRoute,
            true,
            artifacts.gpuBpeDirect,
          );
        }
      }
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
  artifactSelection: {
    speedProfile: artifactSpeed ?? "any",
    strict: artifactSpeed != null,
  },
  artifactSpeeds,
  artifacts,
  metrics: {
    startupColdMs,
    encode1mbMs,
    count1mbMs,
    training100kbNativeMs,
    training100kbRustbpeMs,
    training100kbMinbpeMs,
    training100kbNativeVsRustbpeRatio,
    training100kbNativeVsMinbpeRatio,
    peakRssEncode1mbMb,
    encode1mbMiBPerSec,
    count1mbMiBPerSec,
    gpuMemory: gpuParsed,
    gpuDirectAb,
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
