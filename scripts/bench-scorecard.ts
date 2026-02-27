#!/usr/bin/env bun
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { resolvePath, runCommand, section, writeJson } from "./_lib";

type JsonMap = Record<string, unknown>;

interface CompetitorRow {
  name: string;
  meanMs: number;
  mibPerSec?: number | null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function toNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
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
    )
    .sort();
  if (files.length === 0) {
    return null;
  }
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
    "scripts/bench-ram.ts",
    "scripts/bench-gpu-memory.ts",
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
  gpuMemory: latestResultPath("bench-gpu-memory", { excludes: ["-cuda-"] }),
  gpuOverlap: latestResultPath("bench-gpu-overlap"),
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
const gpuMemory = loadJson(artifacts.gpuMemory);
const gpuOverlap = loadJson(artifacts.gpuOverlap);

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
    ram1mbEncodePeakRss: ramRows,
    gpuMemory,
    gpuMemoryRows,
    gpuOverlap,
    gpuOverlapRows,
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
  `## Winners`,
  `- encode 100KB: ${winner(encode100kbRows)?.name ?? "n/a"}`,
  `- encode 1MB: ${winner(encode1mbRows)?.name ?? "n/a"}`,
  `- count 1MB: ${winner(count1mbRows)?.name ?? "n/a"}`,
  `- decode 128K tok: ${winner(decode128kRows)?.name ?? "n/a"}`,
  `- chat encode: ${winner(chatEncodeRows)?.name ?? "n/a"}`,
  `- chat count: ${winner(chatCountRows)?.name ?? "n/a"}`,
  `- chat limit: ${winner(chatLimitRows)?.name ?? "n/a"}`,
  `- training 100KB: ${winner(training100kbRows)?.name ?? "n/a"}`,
  ``,
  `## Artifacts`,
  ...Object.entries(artifacts).map(([name, path]) => `- ${name}: ${path ?? "missing"}`),
  ``,
];

const outMarkdown = resolvePath("bench", "charts", "scorecard.md");
writeFileSync(outMarkdown, `${markdownRows.join("\n")}\n`, "utf8");

console.log(`Wrote scorecard JSON: ${outJson}`);
console.log(`Wrote scorecard Markdown: ${outMarkdown}`);
