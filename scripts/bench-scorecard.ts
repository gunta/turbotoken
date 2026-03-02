#!/usr/bin/env bun
import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { acquireBenchmarkLock, resolvePath, runCommand, section, writeJson } from "./_lib";

type JsonMap = Record<string, unknown>;

interface CompetitorRow {
  name: string;
  meanMs: number;
  mibPerSec?: number | null;
}

interface GpuBpeDirectProfileRow {
  key: string;
  textKind: string;
  lane: string | null;
  inputBytes: number | null;
  disabledMetalMs: number | null;
  enabledMetalMs: number | null;
  disabledMetalMiBPerSec: number | null;
  enabledMetalMiBPerSec: number | null;
  slowdownPct: number | null;
  throughputRatio: number | null;
  disabledMatchesBaseline: boolean | null;
  enabledMatchesBaseline: boolean | null;
  disabledUsedDirectRoute: boolean | null;
  enabledUsedDirectRoute: boolean | null;
  disabledRouteMedianGpuMiBPerSec: number | null;
  enabledRouteMedianGpuMiBPerSec: number | null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

acquireBenchmarkLock({ label: "bench-scorecard" });

function toNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function toBooleanOrNull(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

function round(value: number, digits = 3): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function latestResultPath(prefix: string, options: { excludes?: string[] } = {}): string | null {
  const excludes = options.excludes ?? [];
  const resultsDir = resolvePath("bench", "results");
  const files = readdirSync(resultsDir)
    .filter(
      (name) =>
        name.startsWith(`${prefix}-`) &&
        name.endsWith(".json") &&
        !name.endsWith(".meta.json") &&
        excludes.every((needle) => !name.includes(needle)),
    );
  if (files.length === 0) {
    return null;
  }
  files.sort((a, b) => {
    const am = statSync(join(resultsDir, a)).mtimeMs;
    const bm = statSync(join(resultsDir, b)).mtimeMs;
    return am - bm;
  });
  return join(resultsDir, files[files.length - 1]);
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

function latestGpuMemoryPath(): string | null {
  const resultsDir = resolvePath("bench", "results");
  const files = readdirSync(resultsDir)
    .filter(
      (name) =>
        name.startsWith("bench-gpu-memory-") &&
        name.endsWith(".json") &&
        !name.endsWith(".meta.json") &&
        !name.includes("-cuda-"),
    )
    .map((name) => ({
      name,
      path: join(resultsDir, name),
      mtimeMs: statSync(join(resultsDir, name)).mtimeMs,
    }))
    .sort((a, b) => b.mtimeMs - a.mtimeMs);

  for (const file of files) {
    const payload = loadJson(file.path);
    if (!payload) {
      continue;
    }
    const env = payload["env"];
    if (!isRecord(env)) {
      return file.path;
    }
    const skipDirect = String(env["TURBOTOKEN_GPU_MEMORY_SKIP_DIRECT_KERNEL"] ?? "").trim().toLowerCase();
    const routeBytes = String(env["TURBOTOKEN_GPU_MEMORY_ROUTE_BYTES"] ?? "").trim();
    if (skipDirect === "1" || skipDirect === "true" || skipDirect === "yes" || skipDirect === "on") {
      continue;
    }
    if (routeBytes.length > 0 && routeBytes !== "1048576") {
      continue;
    }
    return file.path;
  }

  return files.length > 0 ? files[0].path : null;
}

function latestGpuBpeDirectPath(): string | null {
  const resultsDir = resolvePath("bench", "results");
  const files = readdirSync(resultsDir)
    .filter(
      (name) =>
        name.startsWith("bench-gpu-bpe-direct-") &&
        name.endsWith(".json") &&
        !name.endsWith(".meta.json"),
    )
    .map((name) => ({
      name,
      path: join(resultsDir, name),
      mtimeMs: statSync(join(resultsDir, name)).mtimeMs,
    }))
    .sort((a, b) => b.mtimeMs - a.mtimeMs);

  for (const file of files) {
    const payload = loadJson(file.path);
    if (!payload) {
      continue;
    }
    const workloads = payload["workloads"];
    if (isRecord(workloads)) {
      const normalText = workloads["normalText"];
      if (isRecord(normalText)) {
        const enabled = normalText["enabled"];
        if (isRecord(enabled)) {
          const env = enabled["env"];
          if (isRecord(env)) {
            const guard = String(env["TURBOTOKEN_METAL_BPE_DIRECT_LOW_ENTROPY_GUARD"] ?? "").trim().toLowerCase();
            if (guard === "0" || guard === "false" || guard === "no" || guard === "off") {
              continue;
            }
          }
        }
        return file.path;
      }
    }
    const scenarios = payload["scenarios"];
    if (!isRecord(scenarios)) {
      return file.path;
    }
    const enabled = scenarios["enabled"];
    if (!isRecord(enabled)) {
      return file.path;
    }
    const env = enabled["env"];
    if (!isRecord(env)) {
      return file.path;
    }
    const guard = String(env["TURBOTOKEN_METAL_BPE_DIRECT_LOW_ENTROPY_GUARD"] ?? "").trim().toLowerCase();
    if (guard === "0" || guard === "false" || guard === "no" || guard === "off") {
      continue;
    }
    return file.path;
  }

  return files.length > 0 ? files[0].path : null;
}

function parseGpuBpeDirectProfileRow(key: string, value: unknown): GpuBpeDirectProfileRow | null {
  if (!isRecord(value)) {
    return null;
  }
  const comparison = value["comparison"];
  if (!isRecord(comparison)) {
    return null;
  }
  const textKind = String(value["textKind"] ?? key);
  return {
    key,
    textKind,
    lane: typeof value["lane"] === "string" ? String(value["lane"]) : null,
    inputBytes: toNumber(value["inputBytes"]),
    disabledMetalMs: toNumber(comparison["disabledMetalMs"]),
    enabledMetalMs: toNumber(comparison["enabledMetalMs"]),
    disabledMetalMiBPerSec: toNumber(comparison["disabledMetalMiBPerSec"]),
    enabledMetalMiBPerSec: toNumber(comparison["enabledMetalMiBPerSec"]),
    slowdownPct: toNumber(comparison["slowdownPct"]),
    throughputRatio: toNumber(comparison["throughputRatio"]),
    disabledMatchesBaseline: toBooleanOrNull(comparison["disabledMatchesBaseline"]),
    enabledMatchesBaseline: toBooleanOrNull(comparison["enabledMatchesBaseline"]),
    disabledUsedDirectRoute: toBooleanOrNull(comparison["disabledUsedDirectRoute"]),
    enabledUsedDirectRoute: toBooleanOrNull(comparison["enabledUsedDirectRoute"]),
    disabledRouteMedianGpuMiBPerSec: toNumber(comparison["disabledRouteMedianGpuMiBPerSec"]),
    enabledRouteMedianGpuMiBPerSec: toNumber(comparison["enabledRouteMedianGpuMiBPerSec"]),
  };
}

function ratio(baseline: number | null, next: number | null): number | null {
  if (baseline == null || next == null || baseline <= 0) {
    return null;
  }
  return next / baseline;
}

function extractGpuBpeDirectProfiles(payload: JsonMap | null): GpuBpeDirectProfileRow[] {
  if (!payload) {
    return [];
  }
  const workloads = payload["workloads"];
  if (!isRecord(workloads)) {
    return [];
  }
  const rows: GpuBpeDirectProfileRow[] = [];
  for (const [key, value] of Object.entries(workloads)) {
    const row = parseGpuBpeDirectProfileRow(key, value);
    if (row) {
      rows.push(row);
    }
  }
  rows.sort((a, b) => a.textKind.localeCompare(b.textKind));
  return rows;
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

function commandMeanMsByPrefix(payload: JsonMap | null, prefix: string): number | null {
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
    const name = String(row["command"] ?? row["commandName"] ?? "");
    if (!name.startsWith(prefix)) {
      continue;
    }
    const meanSeconds = toNumber(row["mean"]) ?? toNumber(row["meanSeconds"]);
    if (meanSeconds != null) {
      return meanSeconds * 1000;
    }
  }
  return null;
}

function winner(rows: CompetitorRow[]): CompetitorRow | null {
  const valid = rows.filter((row) => Number.isFinite(row.meanMs));
  if (valid.length === 0) {
    return null;
  }
  valid.sort((a, b) => a.meanMs - b.meanMs);
  return valid[0];
}

function toMiBPerSec(meanMs: number | null, totalMiB: number): number | null {
  if (meanMs == null || meanMs <= 0) {
    return null;
  }
  return (totalMiB * 1000) / meanMs;
}

function extractRamRows(payload: JsonMap | null): JsonMap[] {
  if (!payload) {
    return [];
  }
  const rows = payload["rows"];
  if (!Array.isArray(rows)) {
    return [];
  }
  return rows.filter(isRecord);
}

function refreshBenchmarks(): void {
  section("Refreshing scorecard benchmarks");
  const scripts = [
    "scripts/bench-startup.ts",
    "scripts/bench-comparison.ts",
    "scripts/bench-competitors.ts",
    "scripts/bench-chat.ts",
    "scripts/bench-training.ts",
    "scripts/bench-wasm.ts",
    "scripts/bench-ram.ts",
    "scripts/bench-gpu-memory.ts",
    "scripts/bench-gpu-host-overhead.ts",
    "scripts/bench-gpu-overlap.ts",
  ];
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
      throw new Error(`${script} failed with exit code ${result.code}`);
    }
  }
}

const refresh = process.argv.includes("--refresh");
if (refresh) {
  refreshBenchmarks();
}

const artifacts = {
  startupCold: latestResultPath("bench-startup-cold"),
  startupWarm: latestResultPath("bench-startup-warm"),
  comparison: latestResultPath("bench-comparison"),
  competitorsEncode: latestResultPath("bench-competitors-python-encode"),
  competitorsDecode: latestResultPath("bench-competitors-python-decode"),
  competitorsCount: latestResultPath("bench-competitors-python-count"),
  chatHelpers: latestResultPath("bench-chat-helpers"),
  training: latestResultPath("bench-training-python"),
  ram: latestResultPath("bench-ram"),
  wasm: latestResultPath("bench-wasm", { excludes: ["-raw-"] }),
  gpuMemory: latestGpuMemoryPath(),
  gpuHostOverhead: latestResultPath("bench-gpu-host-overhead"),
  gpuOverlap: latestResultPath("bench-gpu-overlap"),
  gpuBpeDirect: latestGpuBpeDirectPath(),
};

const startupCold = loadJson(artifacts.startupCold);
const startupWarm = loadJson(artifacts.startupWarm);
const comparison = loadJson(artifacts.comparison);
const competitorsEncode = loadJson(artifacts.competitorsEncode);
const competitorsDecode = loadJson(artifacts.competitorsDecode);
const competitorsCount = loadJson(artifacts.competitorsCount);
const chatHelpers = loadJson(artifacts.chatHelpers);
const training = loadJson(artifacts.training);
const ram = loadJson(artifacts.ram);
const wasm = loadJson(artifacts.wasm);
const gpuMemory = loadJson(artifacts.gpuMemory);
const gpuHostOverhead = loadJson(artifacts.gpuHostOverhead);
const gpuOverlap = loadJson(artifacts.gpuOverlap);
const gpuBpeDirect = loadJson(artifacts.gpuBpeDirect);

const encode100kbRows: CompetitorRow[] = [
  { name: "turbotoken", meanMs: commandMeanMs(competitorsEncode, "python-encode-100kb-turbotoken") ?? Number.NaN },
  { name: "turbotoken-metal", meanMs: commandMeanMs(competitorsEncode, "python-encode-100kb-turbotoken-metal") ?? Number.NaN },
  { name: "tiktoken", meanMs: commandMeanMs(competitorsEncode, "python-encode-100kb-tiktoken") ?? Number.NaN },
  { name: "rs-bpe", meanMs: commandMeanMs(competitorsEncode, "python-encode-100kb-rs-bpe") ?? Number.NaN },
  { name: "token-dagger", meanMs: commandMeanMs(competitorsEncode, "python-encode-100kb-token-dagger") ?? Number.NaN },
  { name: "gpt-tokenizer", meanMs: commandMeanMs(competitorsEncode, "js-encode-100kb-gpt-tokenizer") ?? Number.NaN },
];

const encode1mbRows: CompetitorRow[] = [
  { name: "turbotoken", meanMs: commandMeanMs(competitorsEncode, "python-encode-1mb-turbotoken") ?? Number.NaN },
  {
    name: "turbotoken-metal",
    meanMs: commandMeanMs(competitorsEncode, "python-encode-1mb-turbotoken-metal") ?? Number.NaN,
  },
  { name: "tiktoken", meanMs: commandMeanMs(competitorsEncode, "python-encode-1mb-tiktoken") ?? Number.NaN },
  { name: "rs-bpe", meanMs: commandMeanMs(competitorsEncode, "python-encode-1mb-rs-bpe") ?? Number.NaN },
  { name: "token-dagger", meanMs: commandMeanMs(competitorsEncode, "python-encode-1mb-token-dagger") ?? Number.NaN },
  { name: "gpt-tokenizer", meanMs: commandMeanMs(competitorsEncode, "js-encode-1mb-gpt-tokenizer") ?? Number.NaN },
].map((row) => ({ ...row, mibPerSec: toMiBPerSec(row.meanMs, 1.0) }));

const count1mbRows: CompetitorRow[] = [
  { name: "turbotoken", meanMs: commandMeanMs(competitorsCount, "python-count-1mb-turbotoken") ?? Number.NaN },
  {
    name: "tiktoken",
    meanMs: commandMeanMs(competitorsCount, "python-count-1mb-tiktoken-via-len-encode") ?? Number.NaN,
  },
  { name: "rs-bpe", meanMs: commandMeanMs(competitorsCount, "python-count-1mb-rs-bpe") ?? Number.NaN },
  {
    name: "token-dagger",
    meanMs: commandMeanMs(competitorsCount, "python-count-1mb-token-dagger-via-len-encode") ?? Number.NaN,
  },
  {
    name: "gpt-tokenizer",
    meanMs: commandMeanMs(competitorsCount, "js-count-1mb-gpt-tokenizer") ?? Number.NaN,
  },
].map((row) => ({ ...row, mibPerSec: toMiBPerSec(row.meanMs, 1.0) }));

const decode128kRows: CompetitorRow[] = [
  {
    name: "turbotoken",
    meanMs: commandMeanMs(competitorsDecode, "python-decode-128000-tok-turbotoken") ?? Number.NaN,
  },
  {
    name: "tiktoken",
    meanMs: commandMeanMs(competitorsDecode, "python-decode-128000-tok-tiktoken") ?? Number.NaN,
  },
  {
    name: "rs-bpe",
    meanMs: commandMeanMs(competitorsDecode, "python-decode-128000-tok-rs-bpe") ?? Number.NaN,
  },
  {
    name: "token-dagger",
    meanMs: commandMeanMs(competitorsDecode, "python-decode-128000-tok-token-dagger") ?? Number.NaN,
  },
  {
    name: "gpt-tokenizer",
    meanMs: commandMeanMs(competitorsDecode, "js-decode-128000-tok-gpt-tokenizer") ?? Number.NaN,
  },
];

const training100kbRows: CompetitorRow[] = [
  {
    name: "turbotoken-native",
    meanMs: commandMeanMs(training, "python-train-english-100kb-turbotoken-native-v320") ?? Number.NaN,
  },
  {
    name: "turbotoken-python",
    meanMs: commandMeanMs(training, "python-train-english-100kb-turbotoken-py-fallback-v320") ?? Number.NaN,
  },
  { name: "rustbpe", meanMs: commandMeanMs(training, "python-train-english-100kb-rustbpe-v320") ?? Number.NaN },
  { name: "minbpe", meanMs: commandMeanMs(training, "python-train-english-100kb-minbpe-v320") ?? Number.NaN },
].map((row) => ({ ...row, mibPerSec: toMiBPerSec(row.meanMs, 100 / 1024) }));

const training1mbNativeMs =
  commandMeanMs(training, "python-train-english-1mb-turbotoken-native-v320") ??
  commandMeanMsByPrefix(training, "python-train-english-1mb-turbotoken-native-v");
const training1mbNativeRows: CompetitorRow[] = [
  {
    name: "turbotoken-native",
    meanMs: training1mbNativeMs ?? Number.NaN,
    mibPerSec: toMiBPerSec(training1mbNativeMs, 1.0),
  },
];

const chatEncodeRows: CompetitorRow[] = [
  { name: "turbotoken", meanMs: commandMeanMs(chatHelpers, "python-chat-encode-turbotoken") ?? Number.NaN },
  { name: "gpt-tokenizer", meanMs: commandMeanMs(chatHelpers, "js-chat-encode-gpt-tokenizer") ?? Number.NaN },
];

const chatCountRows: CompetitorRow[] = [
  { name: "turbotoken", meanMs: commandMeanMs(chatHelpers, "python-chat-count-turbotoken") ?? Number.NaN },
  { name: "gpt-tokenizer", meanMs: commandMeanMs(chatHelpers, "js-chat-count-gpt-tokenizer") ?? Number.NaN },
];

const chatLimitRows: CompetitorRow[] = [
  { name: "turbotoken", meanMs: commandMeanMs(chatHelpers, "python-chat-limit-turbotoken") ?? Number.NaN },
  { name: "gpt-tokenizer", meanMs: commandMeanMs(chatHelpers, "js-chat-limit-gpt-tokenizer") ?? Number.NaN },
];

const comparisonTurbo = commandMeanMs(comparison, "turbotoken-encode-100kb");
const comparisonTiktoken = commandMeanMs(comparison, "tiktoken-encode-100kb");
const comparisonSpeedup =
  comparisonTurbo != null && comparisonTiktoken != null && comparisonTurbo > 0
    ? comparisonTiktoken / comparisonTurbo
    : null;

const startup = {
  cold: {
    turbotokenMs: commandMeanMs(startupCold, "python-startup-turbotoken"),
    tiktokenMs: commandMeanMs(startupCold, "python-startup-tiktoken"),
    rsBpeMs: commandMeanMs(startupCold, "python-startup-rs-bpe"),
    tokenDaggerMs: commandMeanMs(startupCold, "python-startup-token-dagger"),
    gptTokenizerMs: commandMeanMs(startupCold, "js-startup-gpt-tokenizer"),
  },
  warm: {
    turbotokenMs: commandMeanMs(startupWarm, "python-startup-turbotoken"),
    tiktokenMs: commandMeanMs(startupWarm, "python-startup-tiktoken"),
    rsBpeMs: commandMeanMs(startupWarm, "python-startup-rs-bpe"),
    tokenDaggerMs: commandMeanMs(startupWarm, "python-startup-token-dagger"),
    gptTokenizerMs: commandMeanMs(startupWarm, "js-startup-gpt-tokenizer"),
  },
};

const ramRows = extractRamRows(ram).map((row) => ({
  name: String(row["name"] ?? "unknown"),
  medianRssMb: (() => {
    const kb = toNumber(row["medianRssKb"]);
    return kb == null ? null : kb / 1024;
  })(),
  deltaOverBaselineMb: (() => {
    const kb = toNumber(row["deltaOverBaselineKb"]);
    return kb == null ? null : kb / 1024;
  })(),
}));
const training1mbNativeRssMb = (() => {
  const row = ramRows.find((entry) => entry.name.startsWith("python-ram-turbotoken-train-1mb-native-v"));
  return row?.medianRssMb ?? null;
})();

const wasmRows = (() => {
  if (!wasm) {
    return [];
  }
  const benchmark = wasm["benchmark"];
  if (!isRecord(benchmark)) {
    return [];
  }
  const rows = benchmark["rows"];
  if (!Array.isArray(rows)) {
    return [];
  }
  return rows.filter(isRecord).map((row) => ({
    name: String(row["name"] ?? "unknown"),
    category: String(row["category"] ?? "unknown"),
    meanMs: (() => {
      const meanSeconds = toNumber(row["meanSeconds"]);
      return meanSeconds == null ? null : meanSeconds * 1000;
    })(),
    throughputMbPerSec: toNumber(row["throughputMbPerSec"]),
  }));
})();

const wasmNodeRows = wasmRows.filter((row) => row.name.startsWith("node-"));
let wasmBrowserRows = wasmRows.filter((row) => row.name.startsWith("browser-"));
if (wasmBrowserRows.length === 0 && wasm) {
  const browser = wasm["browser"];
  if (isRecord(browser) && Array.isArray(browser["rows"])) {
    wasmBrowserRows = browser["rows"].filter(isRecord).map((row) => ({
      name: String(row["name"] ?? "unknown"),
      category: String(row["category"] ?? "unknown"),
      meanMs: toNumber(row["meanMs"]),
      throughputMbPerSec: toNumber(row["throughputMbPerSec"]),
      status: row["status"],
      reason: row["reason"],
    }));
  }
}

const gpuMemoryRows = (() => {
  if (!gpuMemory) {
    return [];
  }
  const rows = gpuMemory["rows"];
  if (!Array.isArray(rows)) {
    return [];
  }
  return rows.filter(isRecord).map((row) => ({
    name: String(row["name"] ?? "unknown"),
    medianGpuMs: toNumber(row["median_gpu_ms"]),
    medianCpuMs: toNumber(row["median_cpu_ms"]),
    medianGpuMiBPerS: toNumber(row["median_gpu_mib_per_s"]),
    medianCpuMiBPerS: toNumber(row["median_cpu_mib_per_s"]),
    maxDeviceAllocatedMiB: toNumber(row["max_device_allocated_mib"]),
  }));
})();

const gpuOverlapRows = (() => {
  if (!gpuOverlap) {
    return [];
  }
  const rows = gpuOverlap["rows"];
  if (!Array.isArray(rows)) {
    return [];
  }
  return rows.filter(isRecord).map((row) => ({
    name: String(row["name"] ?? "unknown"),
    meanMs: toNumber(row["mean_ms"]),
    mibPerSec: toNumber(row["mib_per_s"]),
  }));
})();

const gpuBpeDirectProfiles = extractGpuBpeDirectProfiles(gpuBpeDirect);
const gpuBpeDirectHeadline =
  gpuBpeDirectProfiles.find((row) => row.textKind === "normal-text") ??
  gpuBpeDirectProfiles.find((row) => row.key === "normalText") ??
  gpuBpeDirectProfiles[0] ??
  null;
const gpuBpeDirectStress =
  gpuBpeDirectProfiles.find((row) => row.textKind === "low-entropy") ??
  gpuBpeDirectProfiles.find((row) => row.key === "lowEntropy") ??
  null;
const gpuBpeDirectLongHeadline =
  gpuBpeDirectProfiles.find((row) => row.key === "normalTextLong") ??
  gpuBpeDirectProfiles.find((row) => row.textKind === "normal-text" && row.lane === "long") ??
  null;
const gpuBpeDirectLongStress =
  gpuBpeDirectProfiles.find((row) => row.key === "lowEntropyLong") ??
  gpuBpeDirectProfiles.find((row) => row.textKind === "low-entropy" && row.lane === "long") ??
  null;
const longHeadlineRouteThroughputRatio = ratio(
  gpuBpeDirectLongHeadline?.disabledRouteMedianGpuMiBPerSec ?? null,
  gpuBpeDirectLongHeadline?.enabledRouteMedianGpuMiBPerSec ?? null,
);
const headlineRouteThroughputRatio = ratio(
  gpuBpeDirectHeadline?.disabledRouteMedianGpuMiBPerSec ?? null,
  gpuBpeDirectHeadline?.enabledRouteMedianGpuMiBPerSec ?? null,
);
const gpuHostDigest = (() => {
  if (!gpuHostOverhead) {
    return null;
  }
  const digest = gpuHostOverhead["digest"];
  return isRecord(digest) ? digest : null;
})();
const gpuHostRows = (() => {
  if (!gpuHostOverhead) {
    return [];
  }
  const rows = gpuHostOverhead["rows"];
  return Array.isArray(rows) ? rows.filter(isRecord) : [];
})();
const gpuHostNormalEnabled = gpuHostRows.find(
  (row) => String(row["name"] ?? "") === "route-normal-text-direct-enabled",
);
const gpuHostNormalDisabled = gpuHostRows.find(
  (row) => String(row["name"] ?? "") === "route-normal-text-direct-disabled",
);

const payload: JsonMap = {
  generatedAt: new Date().toISOString(),
  artifacts,
  summary: {
    note: "Scorecard is generated from latest benchmark artifacts. Repository remains scaffold/optimization-stage, not production-ready.",
    startup,
    comparison100kb: {
      turbotokenMs: comparisonTurbo,
      tiktokenMs: comparisonTiktoken,
      speedup: comparisonSpeedup,
    },
    encode100kb: encode100kbRows,
    encode100kbWinner: winner(encode100kbRows),
    encode1mb: encode1mbRows,
    encode1mbWinner: winner(encode1mbRows),
    count1mb: count1mbRows,
    count1mbWinner: winner(count1mbRows),
    decode128k: decode128kRows,
    decode128kWinner: winner(decode128kRows),
    chatEncode: chatEncodeRows,
    chatEncodeWinner: winner(chatEncodeRows),
    chatCount: chatCountRows,
    chatCountWinner: winner(chatCountRows),
    chatLimit: chatLimitRows,
    chatLimitWinner: winner(chatLimitRows),
    training100kb: training100kbRows,
    training100kbWinner: winner(training100kbRows),
    training1mbNative: training1mbNativeRows,
    training1mbNativeWinner: winner(training1mbNativeRows),
    training1mbNativeRssMb,
    wasm,
    wasmRows,
    wasmNodeRows,
    wasmBrowserRows,
    ram1mbEncodePeakRss: ramRows,
    gpuMemory,
    gpuMemoryRows,
    gpuHostOverhead,
    gpuHostRows,
    gpuOverlap,
    gpuOverlapRows,
    gpuBpeDirect,
    gpuBpeDirectProfiles,
    gpuBpeDirectHeadline,
    gpuBpeDirectStress,
    gpuBpeDirectLongHeadline,
    gpuBpeDirectLongStress,
  },
};

const outJson = resolvePath("bench", "results", `bench-scorecard-${Date.now()}.json`);
writeJson(outJson, payload);

const markdownRows = [
  `# Scorecard`,
  ``,
  `Generated: ${String(payload.generatedAt)}`,
  ``,
  `## Comparison (100KB encode)`,
  `- turbotoken: ${comparisonTurbo == null ? "n/a" : `${round(comparisonTurbo, 1)} ms`}`,
  `- tiktoken: ${comparisonTiktoken == null ? "n/a" : `${round(comparisonTiktoken, 1)} ms`}`,
  `- speedup: ${comparisonSpeedup == null ? "n/a" : `${round(comparisonSpeedup, 2)}x`}`,
  ``,
  `## Startup ("hello" first encode)`,
  `- cold turbotoken: ${
    startup.cold.turbotokenMs == null ? "n/a" : `${round(startup.cold.turbotokenMs, 1)} ms`
  }`,
  `- cold tiktoken: ${startup.cold.tiktokenMs == null ? "n/a" : `${round(startup.cold.tiktokenMs, 1)} ms`}`,
  `- cold gpt-tokenizer (Bun): ${
    startup.cold.gptTokenizerMs == null ? "n/a" : `${round(startup.cold.gptTokenizerMs, 1)} ms`
  }`,
  `- warm turbotoken: ${
    startup.warm.turbotokenMs == null ? "n/a" : `${round(startup.warm.turbotokenMs, 1)} ms`
  }`,
  `- warm tiktoken: ${startup.warm.tiktokenMs == null ? "n/a" : `${round(startup.warm.tiktokenMs, 1)} ms`}`,
  `- warm gpt-tokenizer (Bun): ${
    startup.warm.gptTokenizerMs == null ? "n/a" : `${round(startup.warm.gptTokenizerMs, 1)} ms`
  }`,
  ``,
  `## WASM (Node + Browser)`,
  `- total wasm rows: ${wasmRows.length}`,
  `- node wasm rows: ${wasmNodeRows.length}`,
  `- browser wasm rows: ${wasmBrowserRows.length}`,
  ...wasmNodeRows.slice(0, 8).map((row) =>
    `- node row ${row.name}: ${row.meanMs == null ? "n/a" : `${round(row.meanMs, 2)} ms`} | ${
      row.throughputMbPerSec == null ? "throughput n/a" : `${round(row.throughputMbPerSec, 2)} MB/s`
    }`
  ),
  ...wasmBrowserRows.slice(0, 8).map((row) => {
    const status = typeof row.status === "string" ? row.status : "ok";
    const reason = typeof row.reason === "string" && row.reason.length > 0 ? ` (${row.reason})` : "";
    const metrics = status === "ok"
      ? ` | ${row.meanMs == null ? "n/a" : `${round(row.meanMs, 2)} ms`} | ${
        row.throughputMbPerSec == null ? "throughput n/a" : `${round(row.throughputMbPerSec, 2)} MB/s`
      }`
      : "";
    return `- browser row ${row.name}: ${status}${reason}${metrics}`;
  }),
  ``,
  `## GPU Direct A/B (Headline: normal-text)`,
  `- profile count: ${gpuBpeDirectProfiles.length}`,
  `- headline profile: ${gpuBpeDirectHeadline?.textKind ?? "n/a"}`,
  `- headline disabled: ${
    gpuBpeDirectHeadline?.disabledMetalMs == null
      ? "n/a"
      : `${round(gpuBpeDirectHeadline.disabledMetalMs, 2)} ms (${gpuBpeDirectHeadline.disabledMetalMiBPerSec == null ? "MiB/s n/a" : `${round(gpuBpeDirectHeadline.disabledMetalMiBPerSec, 3)} MiB/s`})`
  }`,
  `- headline enabled: ${
    gpuBpeDirectHeadline?.enabledMetalMs == null
      ? "n/a"
      : `${round(gpuBpeDirectHeadline.enabledMetalMs, 2)} ms (${gpuBpeDirectHeadline.enabledMetalMiBPerSec == null ? "MiB/s n/a" : `${round(gpuBpeDirectHeadline.enabledMetalMiBPerSec, 3)} MiB/s`})`
  }`,
  `- headline slowdown: ${gpuBpeDirectHeadline?.slowdownPct == null ? "n/a" : `${round(gpuBpeDirectHeadline.slowdownPct, 2)}%`}`,
  `- headline throughput ratio (enabled/disabled): ${gpuBpeDirectHeadline?.throughputRatio == null ? "n/a" : `${round(gpuBpeDirectHeadline.throughputRatio, 3)}x`}`,
  `- headline route disabled (GPU-only): ${
    gpuBpeDirectHeadline?.disabledRouteMedianGpuMiBPerSec == null
      ? "n/a"
      : `${round(gpuBpeDirectHeadline.disabledRouteMedianGpuMiBPerSec, 3)} MiB/s`
  }`,
  `- headline route enabled (GPU-only): ${
    gpuBpeDirectHeadline?.enabledRouteMedianGpuMiBPerSec == null
      ? "n/a"
      : `${round(gpuBpeDirectHeadline.enabledRouteMedianGpuMiBPerSec, 3)} MiB/s`
  }`,
  `- headline route throughput ratio (enabled/disabled): ${
    headlineRouteThroughputRatio == null ? "n/a" : `${round(headlineRouteThroughputRatio, 3)}x`
  }`,
  `- stress profile: ${gpuBpeDirectStress?.textKind ?? "n/a"}`,
  `- stress slowdown: ${gpuBpeDirectStress?.slowdownPct == null ? "n/a" : `${round(gpuBpeDirectStress.slowdownPct, 2)}%`}`,
  `- stress throughput ratio (enabled/disabled): ${gpuBpeDirectStress?.throughputRatio == null ? "n/a" : `${round(gpuBpeDirectStress.throughputRatio, 3)}x`}`,
  `- long-lane headline key: ${gpuBpeDirectLongHeadline?.key ?? "n/a"}`,
  `- long-lane bytes: ${gpuBpeDirectLongHeadline?.inputBytes == null ? "n/a" : `${Math.round(gpuBpeDirectLongHeadline.inputBytes).toLocaleString()}`}`,
  `- long-lane disabled: ${
    gpuBpeDirectLongHeadline?.disabledMetalMs == null
      ? "n/a"
      : `${round(gpuBpeDirectLongHeadline.disabledMetalMs, 2)} ms (${gpuBpeDirectLongHeadline.disabledMetalMiBPerSec == null ? "MiB/s n/a" : `${round(gpuBpeDirectLongHeadline.disabledMetalMiBPerSec, 3)} MiB/s`})`
  }`,
  `- long-lane enabled: ${
    gpuBpeDirectLongHeadline?.enabledMetalMs == null
      ? "n/a"
      : `${round(gpuBpeDirectLongHeadline.enabledMetalMs, 2)} ms (${gpuBpeDirectLongHeadline.enabledMetalMiBPerSec == null ? "MiB/s n/a" : `${round(gpuBpeDirectLongHeadline.enabledMetalMiBPerSec, 3)} MiB/s`})`
  }`,
  `- long-lane slowdown: ${gpuBpeDirectLongHeadline?.slowdownPct == null ? "n/a" : `${round(gpuBpeDirectLongHeadline.slowdownPct, 2)}%`}`,
  `- long-lane throughput ratio (enabled/disabled): ${gpuBpeDirectLongHeadline?.throughputRatio == null ? "n/a" : `${round(gpuBpeDirectLongHeadline.throughputRatio, 3)}x`}`,
  `- long-lane route disabled (GPU-only): ${
    gpuBpeDirectLongHeadline?.disabledRouteMedianGpuMiBPerSec == null
      ? "n/a"
      : `${round(gpuBpeDirectLongHeadline.disabledRouteMedianGpuMiBPerSec, 3)} MiB/s`
  }`,
  `- long-lane route enabled (GPU-only): ${
    gpuBpeDirectLongHeadline?.enabledRouteMedianGpuMiBPerSec == null
      ? "n/a"
      : `${round(gpuBpeDirectLongHeadline.enabledRouteMedianGpuMiBPerSec, 3)} MiB/s`
  }`,
  `- long-lane route throughput ratio (enabled/disabled): ${
    longHeadlineRouteThroughputRatio == null ? "n/a" : `${round(longHeadlineRouteThroughputRatio, 3)}x`
  }`,
  `- long-lane stress key: ${gpuBpeDirectLongStress?.key ?? "n/a"}`,
  `- long-lane stress slowdown: ${gpuBpeDirectLongStress?.slowdownPct == null ? "n/a" : `${round(gpuBpeDirectLongStress.slowdownPct, 2)}%`}`,
  `- long-lane stress throughput ratio (enabled/disabled): ${gpuBpeDirectLongStress?.throughputRatio == null ? "n/a" : `${round(gpuBpeDirectLongStress.throughputRatio, 3)}x`}`,
  ``,
  `## GPU Host Overhead`,
  `- digest speedup (raw/cached): ${
    toNumber(gpuHostDigest?.["speedup_raw_vs_cached"]) == null
      ? "n/a"
      : `${round(toNumber(gpuHostDigest?.["speedup_raw_vs_cached"]) ?? Number.NaN, 2)}x`
  }`,
  `- rank table cold init: ${
    toNumber((isRecord(gpuHostOverhead?.["rank_table_init"]) ? gpuHostOverhead?.["rank_table_init"] : null)?.["cold_ms"]) == null
      ? "n/a"
      : `${round(toNumber((isRecord(gpuHostOverhead?.["rank_table_init"]) ? gpuHostOverhead?.["rank_table_init"] : null)?.["cold_ms"]) ?? Number.NaN, 3)} ms`
  }`,
  `- rank table warm init: ${
    toNumber((isRecord(gpuHostOverhead?.["rank_table_init"]) ? gpuHostOverhead?.["rank_table_init"] : null)?.["warm_ms"]) == null
      ? "n/a"
      : `${round(toNumber((isRecord(gpuHostOverhead?.["rank_table_init"]) ? gpuHostOverhead?.["rank_table_init"] : null)?.["warm_ms"]) ?? Number.NaN, 3)} ms`
  }`,
  `- normal-text direct disabled host-overhead: ${
    toNumber(gpuHostNormalDisabled?.["mean_host_overhead_ms"]) == null
      ? "n/a"
      : `${round(toNumber(gpuHostNormalDisabled?.["mean_host_overhead_ms"]) ?? Number.NaN, 3)} ms`
  }`,
  `- normal-text direct enabled host-overhead: ${
    toNumber(gpuHostNormalEnabled?.["mean_host_overhead_ms"]) == null
      ? "n/a"
      : `${round(toNumber(gpuHostNormalEnabled?.["mean_host_overhead_ms"]) ?? Number.NaN, 3)} ms`
  }`,
  ``,
  `## Winners`,
  `- encode 100KB: ${winner(encode100kbRows)?.name ?? "n/a"}`,
  `- encode 1MB: ${winner(encode1mbRows)?.name ?? "n/a"}`,
  `- count 1MB: ${winner(count1mbRows)?.name ?? "n/a"}`,
  `- decode 128K tok: ${winner(decode128kRows)?.name ?? "n/a"}`,
  `- chat encode: ${winner(chatEncodeRows)?.name ?? "n/a"}`,
  `- chat count: ${winner(chatCountRows)?.name ?? "n/a"}`,
  `- chat limit: ${winner(chatLimitRows)?.name ?? "n/a"}`,
  `- training 100KB: ${winner(training100kbRows)?.name ?? "n/a"}`,
  `- training 1MB native: ${winner(training1mbNativeRows)?.name ?? "n/a"}`,
  `- training 1MB native latency: ${
    training1mbNativeRows[0]?.meanMs != null && Number.isFinite(training1mbNativeRows[0].meanMs)
      ? `${round(training1mbNativeRows[0].meanMs, 2)} ms`
      : "n/a"
  }`,
  `- training 1MB native throughput: ${
    training1mbNativeRows[0]?.mibPerSec != null && Number.isFinite(training1mbNativeRows[0].mibPerSec)
      ? `${round(training1mbNativeRows[0].mibPerSec, 3)} MiB/s`
      : "n/a"
  }`,
  `- training 1MB native RSS: ${training1mbNativeRssMb == null ? "n/a" : `${round(training1mbNativeRssMb, 2)} MB`}`,
  ``,
  `## Artifacts`,
  ...Object.entries(artifacts).map(([name, path]) => `- ${name}: ${path ?? "missing"}`),
  ``,
];

const outMarkdown = resolvePath("bench", "charts", "scorecard.md");
writeFileSync(outMarkdown, `${markdownRows.join("\n")}\n`, "utf8");

console.log(`Wrote scorecard JSON: ${outJson}`);
console.log(`Wrote scorecard Markdown: ${outMarkdown}`);
