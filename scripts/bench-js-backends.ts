#!/usr/bin/env bun
import { performance } from "node:perf_hooks";
import { statSync } from "node:fs";
import { ensureFixtures } from "./_fixtures";
import { acquireBenchmarkLock, resolvePath, section, writeJson } from "./_lib";
import { loadNative } from "../wrappers/js/src/native-loader";
import { loadWasm } from "../wrappers/js/src/wasm-loader";

interface BackendBenchRow {
  name: string;
  mode: "native" | "wasm";
  workload: "utf8-encode-1mb" | "bpe-encode-100kb";
  runs: number;
  warmup: number;
  meanMs: number;
  minMs: number;
  maxMs: number;
  mibPerSec: number;
}

function mean(values: readonly number[]): number {
  if (values.length === 0) {
    return 0;
  }
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function mibPerSec(bytes: number, ms: number): number {
  if (ms <= 0) {
    return 0;
  }
  return (bytes / (1024 * 1024)) / (ms / 1000);
}

function parseRuns(name: string, fallback: number): number {
  const raw = process.env[name]?.trim();
  if (!raw) {
    return fallback;
  }
  const value = Number.parseInt(raw, 10);
  if (!Number.isFinite(value) || value <= 0) {
    return fallback;
  }
  return value;
}

async function ensureRankPayload(path: string, url: string): Promise<void> {
  try {
    statSync(path);
    return;
  } catch {
    // download
  }
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to fetch rank payload: HTTP ${response.status}`);
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  await Bun.write(path, bytes);
}

acquireBenchmarkLock({ label: "bench-js-backends" });
section("JS backend benchmark (native vs wasm)");

const outputPath = resolvePath("bench", "results", `bench-js-backends-${Date.now()}.json`);
const warmup = parseRuns("TURBOTOKEN_JS_BACKEND_WARMUP", 1);
const runs = parseRuns("TURBOTOKEN_JS_BACKEND_RUNS", 5);

await ensureFixtures();
const fixture1mbPath = resolvePath("bench", "fixtures", "english-1mb.txt");
const fixture100kbPath = resolvePath("bench", "fixtures", "english-100kb.txt");
const text1mb = new Uint8Array(await Bun.file(fixture1mbPath).arrayBuffer());
const text100kb = new Uint8Array(await Bun.file(fixture100kbPath).arrayBuffer());

const rankPath = resolvePath("bench", "results", "cache", "o200k_base.tiktoken");
await ensureRankPayload(rankPath, "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken");
const rankPayload = new Uint8Array(await Bun.file(rankPath).arrayBuffer());

const ext = process.platform === "darwin" ? "dylib" : process.platform === "linux" ? "so" : process.platform === "win32" ? "dll" : null;
if (!ext) {
  throw new Error(`unsupported platform for native backend benchmark: ${process.platform}`);
}
const nativeName = ext === "dll" ? "turbotoken.dll" : `libturbotoken.${ext}`;
const nativePath = resolvePath("js", "native", "host", `${process.platform}-${process.arch}`, nativeName);

const native = await loadNative({ nativeLibPath: nativePath, forceReload: true });
const wasmFullPath = resolvePath("zig-out", "bin", "turbotoken.wasm");
const wasm = await loadWasm({ wasmPath: wasmFullPath, forceReload: true });

const rows: BackendBenchRow[] = [];

function runRow(
  mode: "native" | "wasm",
  workload: "utf8-encode-1mb" | "bpe-encode-100kb",
  bytes: number,
  fn: () => void,
): void {
  for (let i = 0; i < warmup; i += 1) {
    fn();
  }
  const samples: number[] = [];
  for (let i = 0; i < runs; i += 1) {
    const t0 = performance.now();
    fn();
    samples.push(performance.now() - t0);
  }
  const avg = mean(samples);
  rows.push({
    name: `${mode}-${workload}`,
    mode,
    workload,
    runs,
    warmup,
    meanMs: avg,
    minMs: Math.min(...samples),
    maxMs: Math.max(...samples),
    mibPerSec: mibPerSec(bytes, avg),
  });
}

runRow("native", "utf8-encode-1mb", text1mb.byteLength, () => {
  native.encodeUtf8Bytes(text1mb);
});
runRow("wasm", "utf8-encode-1mb", text1mb.byteLength, () => {
  wasm.encodeUtf8Bytes(text1mb);
});
runRow("native", "bpe-encode-100kb", text100kb.byteLength, () => {
  native.encodeBpeFromRanks(rankPayload, text100kb);
});
runRow("wasm", "bpe-encode-100kb", text100kb.byteLength, () => {
  wasm.encodeBpeFromRanks(rankPayload, text100kb);
});

writeJson(outputPath, {
  generatedAt: new Date().toISOString(),
  status: "ok",
  environment: {
    platform: process.platform,
    arch: process.arch,
    runtime: "bun",
  },
  inputs: {
    fixture1mbPath,
    fixture100kbPath,
    rankPath,
    nativePath,
    wasmFullPath,
  },
  rows,
  note: "Bun runtime backend comparison between bundled host native bridge and WASM bridge.",
});

for (const row of rows) {
  console.log(`${row.name}: ${row.meanMs.toFixed(2)} ms (${row.mibPerSec.toFixed(2)} MiB/s)`);
}
console.log(`Wrote JS backend benchmark record: ${outputPath}`);
