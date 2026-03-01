#!/usr/bin/env bun
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { performance } from "node:perf_hooks";
import { ensureFixtures } from "./_fixtures";
import {
  acquireBenchmarkLock,
  commandExists,
  resolvePath,
  runCommand,
  runShell,
  section,
  writeJson,
  zigExecutable,
} from "./_lib";

interface BenchCase {
  name: string;
  command: string;
  category: "startup" | "throughput";
  bytesProcessed?: number;
}

interface BenchRow {
  name: string;
  command: string;
  category: "startup" | "throughput";
  runs: number;
  warmup: number;
  meanSeconds: number;
  stddevSeconds: number;
  minSeconds: number;
  maxSeconds: number;
  bytesProcessed: number | null;
}

interface HyperfineResult {
  command: string;
  mean: number;
  stddev: number;
  min: number;
  max: number;
  times: number[];
}

interface HyperfineExport {
  results: HyperfineResult[];
}

interface MemorySample {
  run: number;
  exitCode: number;
  maxRssKb: number | null;
  stdout: string;
  stderr: string;
}

interface MemoryRow {
  name: string;
  command: string;
  runs: number;
  successfulRuns: number;
  medianRssKb: number | null;
  meanRssKb: number | null;
  minRssKb: number | null;
  maxRssKb: number | null;
  samples: MemorySample[];
}

acquireBenchmarkLock({ label: "bench-wasm" });

const fastMode = ["1", "true", "yes", "on"].includes(
  (process.env.TURBOTOKEN_BENCH_FAST ?? "").trim().toLowerCase(),
);

function mean(values: readonly number[]): number {
  if (values.length === 0) {
    return 0;
  }
  return values.reduce((acc, value) => acc + value, 0) / values.length;
}

function stddev(values: readonly number[]): number {
  if (values.length <= 1) {
    return 0;
  }
  const avg = mean(values);
  const variance = values.reduce((acc, value) => acc + ((value - avg) ** 2), 0) / values.length;
  return Math.sqrt(variance);
}

function median(values: readonly number[]): number | null {
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

function parseMaxRssKb(stderr: string): number | null {
  const macMatch = stderr.match(/(\d+)\s+maximum resident set size/);
  if (macMatch) {
    return Number(macMatch[1]) / 1024;
  }

  const linuxMatch = stderr.match(/Maximum resident set size \(kbytes\):\s+(\d+)/);
  if (linuxMatch) {
    return Number(linuxMatch[1]);
  }

  return null;
}

async function ensureRankPayload(path: string, url: string): Promise<{ path: string; bytes: number } | null> {
  if (existsSync(path)) {
    return { path, bytes: statSync(path).size };
  }

  const response = await fetch(url);
  if (!response.ok) {
    return null;
  }

  const payload = new Uint8Array(await response.arrayBuffer());
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, payload);
  return { path, bytes: payload.byteLength };
}

function resolveHyperfineCommand(): string | null {
  const home = process.env.HOME ?? "";
  const candidates = [
    "hyperfine",
    "/opt/homebrew/bin/hyperfine",
    `${home}/.proto/tools/hyperfine/1.20.0/hyperfine-v1.20.0-aarch64-apple-darwin/hyperfine`,
    `${home}/.proto/tools/hyperfine/1.19.0/hyperfine-v1.19.0-aarch64-apple-darwin/hyperfine`,
  ];

  for (const candidate of candidates) {
    if (candidate.includes("/") && !existsSync(candidate)) {
      continue;
    }
    const probe = runCommand(candidate, ["--version"], { allowFailure: true });
    if (probe.code === 0) {
      return candidate;
    }
  }

  return null;
}

function runManualBench(cases: readonly BenchCase[], warmup: number, runs: number): BenchRow[] {
  const rows: BenchRow[] = [];
  for (const benchCase of cases) {
    for (let i = 0; i < warmup; i += 1) {
      runShell(benchCase.command);
    }

    const times: number[] = [];
    for (let i = 0; i < runs; i += 1) {
      const start = performance.now();
      runShell(benchCase.command);
      times.push((performance.now() - start) / 1000);
    }

    rows.push({
      name: benchCase.name,
      command: benchCase.command,
      category: benchCase.category,
      runs,
      warmup,
      meanSeconds: mean(times),
      stddevSeconds: stddev(times),
      minSeconds: Math.min(...times),
      maxSeconds: Math.max(...times),
      bytesProcessed: benchCase.bytesProcessed ?? null,
    });
  }
  return rows;
}

function runHyperfineBench(
  hyperfine: string,
  cases: readonly BenchCase[],
  warmup: number,
  runs: number,
  maxRuns: number | null,
  rawPath: string,
): BenchRow[] | null {
  const args = [
    "--warmup",
    String(warmup),
    "--min-runs",
    String(runs),
    "--export-json",
    rawPath,
  ];
  if (maxRuns != null) {
    args.push("--max-runs", String(maxRuns));
  }

  for (const benchCase of cases) {
    args.push("--command-name", benchCase.name, benchCase.command);
  }

  const result = runCommand(hyperfine, args, { allowFailure: true });
  const output = [result.stdout.trim(), result.stderr.trim()].filter(Boolean).join("\n");
  if (output.length > 0) {
    console.log(output);
  }
  if (result.code !== 0 || !existsSync(rawPath)) {
    return null;
  }

  const parsed = JSON.parse(readFileSync(rawPath, "utf8")) as HyperfineExport;
  const byName = new Map<string, BenchCase>();
  for (const benchCase of cases) {
    byName.set(benchCase.name, benchCase);
  }

  const rows: BenchRow[] = [];
  for (const row of parsed.results) {
    const benchCase = byName.get(row.command);
    if (!benchCase) {
      continue;
    }
    rows.push({
      name: benchCase.name,
      command: benchCase.command,
      category: benchCase.category,
      runs: row.times.length,
      warmup,
      meanSeconds: row.mean,
      stddevSeconds: row.stddev,
      minSeconds: row.min,
      maxSeconds: row.max,
      bytesProcessed: benchCase.bytesProcessed ?? null,
    });
  }

  return rows;
}

function runMemoryRows(rows: readonly { name: string; command: string }[], runs: number): MemoryRow[] {
  const timeFlag = process.platform === "darwin" ? "-l" : "-v";
  const out: MemoryRow[] = [];

  for (const row of rows) {
    const samples: MemorySample[] = [];
    for (let i = 0; i < runs; i += 1) {
      const result = runShell(`/usr/bin/time ${timeFlag} ${row.command}`, { allowFailure: true });
      samples.push({
        run: i + 1,
        exitCode: result.code,
        maxRssKb: parseMaxRssKb(result.stderr),
        stdout: result.stdout,
        stderr: result.stderr,
      });
    }

    const successful = samples
      .filter((sample) => sample.exitCode === 0 && sample.maxRssKb != null)
      .map((sample) => sample.maxRssKb as number);

    out.push({
      name: row.name,
      command: row.command,
      runs,
      successfulRuns: successful.length,
      medianRssKb: median(successful),
      meanRssKb: successful.length > 0 ? mean(successful) : null,
      minRssKb: successful.length > 0 ? Math.min(...successful) : null,
      maxRssKb: successful.length > 0 ? Math.max(...successful) : null,
      samples,
    });
  }

  return out;
}

ensureFixtures();
section("WASM benchmark");

const zig = zigExecutable();
const outputPath = resolvePath("bench", "results", `bench-wasm-${Date.now()}.json`);
if (!commandExists(zig)) {
  writeJson(outputPath, {
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: "zig executable not found",
  });
  console.warn("zig executable not found; wrote skipped benchmark record.");
  process.exit(0);
}

const buildResult = runCommand(zig, ["build", "wasm", "-Doptimize=ReleaseSmall"], { allowFailure: true });
const wasmPath = resolvePath("zig-out", "bin", "turbotoken.wasm");
if (buildResult.code !== 0 || !existsSync(wasmPath)) {
  writeJson(outputPath, {
    generatedAt: new Date().toISOString(),
    status: "failed",
    reason: "wasm build failed",
    wasmPath,
    stdout: buildResult.stdout,
    stderr: buildResult.stderr,
  });
  console.warn(`WASM build failed; recorded details at ${outputPath}`);
  process.exit(0);
}

const wasmBytes = statSync(wasmPath).size;
const fixture100kb = resolvePath("bench", "fixtures", "english-100kb.txt");
const fixture1mb = resolvePath("bench", "fixtures", "english-1mb.txt");
const fixture100kbBytes = statSync(fixture100kb).size;
const fixture1mbBytes = statSync(fixture1mb).size;
const rankPayloadUrl = process.env.TURBOTOKEN_WASM_RANK_URL?.trim()
  || "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken";
const rankPayloadPath = process.env.TURBOTOKEN_WASM_RANK_PATH?.trim()
  || resolvePath("bench", "results", "cache", "o200k_base.tiktoken");
const rankPayloadInfo = await ensureRankPayload(rankPayloadPath, rankPayloadUrl);
if (rankPayloadInfo === null) {
  console.warn(`Skipping WASM BPE rows: unable to fetch rank payload from ${rankPayloadUrl}`);
}

const wasmStartupCommand =
  `bun -e "import { loadWasm } from './js/src/wasm-loader';const bridge=await loadWasm({wasmPath:'${wasmPath}',forceReload:true});bridge.encodeUtf8Bytes(Uint8Array.of(104,101,108,108,111));"`;
const jsStartupCommand =
  `bun -e "Array.from(new TextEncoder().encode('hello'));"`;
const nodeAvailable = commandExists("node");
const nodeStartupCommand = nodeAvailable
  ? `node --input-type=module -e "import { readFile } from 'node:fs/promises';const wasm=await readFile('${wasmPath}');const {instance}=await WebAssembly.instantiate(wasm,{});const e=instance.exports;const data=Buffer.from('hello');const textPtr=e.turbotoken_wasm_alloc(data.length);new Uint8Array(e.memory.buffer).set(data,textPtr);const needed=e.turbotoken_encode_utf8_bytes(textPtr,data.length,0,0);if(needed<0) throw new Error('encode failed');e.turbotoken_wasm_free(textPtr,data.length);"`
  : null;
const wasmStartupBpeCommand = rankPayloadInfo
  ? `bun -e "import { loadWasm } from './js/src/wasm-loader';const bridge=await loadWasm({wasmPath:'${wasmPath}',forceReload:true});const ranks=new Uint8Array(await Bun.file('${rankPayloadPath}').arrayBuffer());bridge.encodeBpeFromRanks(ranks,Uint8Array.of(104,101,108,108,111));"`
  : null;
const nodeStartupBpeCommand = nodeAvailable && rankPayloadInfo
  ? `node --input-type=module -e "import { readFile } from 'node:fs/promises';const wasm=await readFile('${wasmPath}');const ranks=new Uint8Array(await readFile('${rankPayloadPath}'));const {instance}=await WebAssembly.instantiate(wasm,{});const e=instance.exports;const text=Buffer.from('hello');const rankPtr=e.turbotoken_wasm_alloc(ranks.length);const textPtr=e.turbotoken_wasm_alloc(text.length);new Uint8Array(e.memory.buffer).set(ranks,rankPtr);new Uint8Array(e.memory.buffer).set(text,textPtr);const needed=e.turbotoken_encode_bpe_from_ranks(rankPtr,ranks.length,textPtr,text.length,0,0);if(needed<0) throw new Error('bpe encode failed');e.turbotoken_wasm_free(textPtr,text.length);e.turbotoken_wasm_free(rankPtr,ranks.length);"`
  : null;
const wasmEncode100kbCommand =
  `bun -e "import { loadWasm } from './js/src/wasm-loader';const bridge=await loadWasm({wasmPath:'${wasmPath}',forceReload:true});const bytes=new Uint8Array(await Bun.file('${fixture100kb}').arrayBuffer());bridge.encodeUtf8Bytes(bytes);"`;
const jsEncode100kbCommand =
  `bun -e "const text=await Bun.file('${fixture100kb}').text();Array.from(new TextEncoder().encode(text));"`;
const nodeEncode100kbCommand = nodeAvailable
  ? `node --input-type=module -e "import { readFile } from 'node:fs/promises';const wasm=await readFile('${wasmPath}');const bytes=await readFile('${fixture100kb}');const {instance}=await WebAssembly.instantiate(wasm,{});const e=instance.exports;const textPtr=e.turbotoken_wasm_alloc(bytes.length);new Uint8Array(e.memory.buffer).set(bytes,textPtr);const needed=e.turbotoken_encode_utf8_bytes(textPtr,bytes.length,0,0);if(needed<0) throw new Error('encode failed');e.turbotoken_wasm_free(textPtr,bytes.length);"`
  : null;
const wasmEncode1mbCommand =
  `bun -e "import { loadWasm } from './js/src/wasm-loader';const bridge=await loadWasm({wasmPath:'${wasmPath}',forceReload:true});const bytes=new Uint8Array(await Bun.file('${fixture1mb}').arrayBuffer());bridge.encodeUtf8Bytes(bytes);"`;
const jsEncode1mbCommand =
  `bun -e "const text=await Bun.file('${fixture1mb}').text();Array.from(new TextEncoder().encode(text));"`;
const nodeEncode1mbCommand = nodeAvailable
  ? `node --input-type=module -e "import { readFile } from 'node:fs/promises';const wasm=await readFile('${wasmPath}');const bytes=await readFile('${fixture1mb}');const {instance}=await WebAssembly.instantiate(wasm,{});const e=instance.exports;const textPtr=e.turbotoken_wasm_alloc(bytes.length);new Uint8Array(e.memory.buffer).set(bytes,textPtr);const needed=e.turbotoken_encode_utf8_bytes(textPtr,bytes.length,0,0);if(needed<0) throw new Error('encode failed');e.turbotoken_wasm_free(textPtr,bytes.length);"`
  : null;
const wasmBpeEncode100kbCommand = rankPayloadInfo
  ? `bun -e "import { loadWasm } from './js/src/wasm-loader';const bridge=await loadWasm({wasmPath:'${wasmPath}',forceReload:true});const ranks=new Uint8Array(await Bun.file('${rankPayloadPath}').arrayBuffer());const text=new Uint8Array(await Bun.file('${fixture100kb}').arrayBuffer());bridge.encodeBpeFromRanks(ranks,text);"`
  : null;
const wasmBpeEncode1mbCommand = rankPayloadInfo
  ? `bun -e "import { loadWasm } from './js/src/wasm-loader';const bridge=await loadWasm({wasmPath:'${wasmPath}',forceReload:true});const ranks=new Uint8Array(await Bun.file('${rankPayloadPath}').arrayBuffer());const text=new Uint8Array(await Bun.file('${fixture1mb}').arrayBuffer());bridge.encodeBpeFromRanks(ranks,text);"`
  : null;
const nodeBpeEncode100kbCommand = nodeAvailable && rankPayloadInfo
  ? `node --input-type=module -e "import { readFile } from 'node:fs/promises';const wasm=await readFile('${wasmPath}');const ranks=new Uint8Array(await readFile('${rankPayloadPath}'));const input=await readFile('${fixture100kb}');const {instance}=await WebAssembly.instantiate(wasm,{});const e=instance.exports;const rankPtr=e.turbotoken_wasm_alloc(ranks.length);const textPtr=e.turbotoken_wasm_alloc(input.length);new Uint8Array(e.memory.buffer).set(ranks,rankPtr);new Uint8Array(e.memory.buffer).set(input,textPtr);const needed=e.turbotoken_encode_bpe_from_ranks(rankPtr,ranks.length,textPtr,input.length,0,0);if(needed<0) throw new Error('bpe encode failed');e.turbotoken_wasm_free(textPtr,input.length);e.turbotoken_wasm_free(rankPtr,ranks.length);"`
  : null;
const nodeBpeEncode1mbCommand = nodeAvailable && rankPayloadInfo
  ? `node --input-type=module -e "import { readFile } from 'node:fs/promises';const wasm=await readFile('${wasmPath}');const ranks=new Uint8Array(await readFile('${rankPayloadPath}'));const input=await readFile('${fixture1mb}');const {instance}=await WebAssembly.instantiate(wasm,{});const e=instance.exports;const rankPtr=e.turbotoken_wasm_alloc(ranks.length);const textPtr=e.turbotoken_wasm_alloc(input.length);new Uint8Array(e.memory.buffer).set(ranks,rankPtr);new Uint8Array(e.memory.buffer).set(input,textPtr);const needed=e.turbotoken_encode_bpe_from_ranks(rankPtr,ranks.length,textPtr,input.length,0,0);if(needed<0) throw new Error('bpe encode failed');e.turbotoken_wasm_free(textPtr,input.length);e.turbotoken_wasm_free(rankPtr,ranks.length);"`
  : null;

const benchCases: BenchCase[] = [
  {
    name: "wasm-startup-first-encode-hello",
    command: wasmStartupCommand,
    category: "startup",
  },
  {
    name: "js-startup-textencoder-hello",
    command: jsStartupCommand,
    category: "startup",
  },
  {
    name: "wasm-encode-utf8-bytes-100kb",
    command: wasmEncode100kbCommand,
    category: "throughput",
    bytesProcessed: fixture100kbBytes,
  },
  {
    name: "js-textencoder-u32-100kb",
    command: jsEncode100kbCommand,
    category: "throughput",
    bytesProcessed: fixture100kbBytes,
  },
  {
    name: "wasm-encode-utf8-bytes-1mb",
    command: wasmEncode1mbCommand,
    category: "throughput",
    bytesProcessed: fixture1mbBytes,
  },
  {
    name: "js-textencoder-u32-1mb",
    command: jsEncode1mbCommand,
    category: "throughput",
    bytesProcessed: fixture1mbBytes,
  },
];
if (wasmStartupBpeCommand !== null) {
  benchCases.push({
    name: "wasm-startup-first-bpe-encode-hello",
    command: wasmStartupBpeCommand,
    category: "startup",
  });
}
if (nodeStartupCommand !== null) {
  benchCases.push({
    name: "node-wasm-startup-first-encode-hello",
    command: nodeStartupCommand,
    category: "startup",
  });
}
if (nodeStartupBpeCommand !== null) {
  benchCases.push({
    name: "node-wasm-startup-first-bpe-encode-hello",
    command: nodeStartupBpeCommand,
    category: "startup",
  });
}
if (nodeEncode100kbCommand !== null) {
  benchCases.push({
    name: "node-wasm-encode-utf8-bytes-100kb",
    command: nodeEncode100kbCommand,
    category: "throughput",
    bytesProcessed: fixture100kbBytes,
  });
}
if (nodeEncode1mbCommand !== null) {
  benchCases.push({
    name: "node-wasm-encode-utf8-bytes-1mb",
    command: nodeEncode1mbCommand,
    category: "throughput",
    bytesProcessed: fixture1mbBytes,
  });
}
if (wasmBpeEncode100kbCommand !== null) {
  benchCases.push({
    name: "wasm-encode-bpe-o200k-100kb",
    command: wasmBpeEncode100kbCommand,
    category: "throughput",
    bytesProcessed: fixture100kbBytes,
  });
}
if (wasmBpeEncode1mbCommand !== null) {
  benchCases.push({
    name: "wasm-encode-bpe-o200k-1mb",
    command: wasmBpeEncode1mbCommand,
    category: "throughput",
    bytesProcessed: fixture1mbBytes,
  });
}
if (nodeBpeEncode100kbCommand !== null) {
  benchCases.push({
    name: "node-wasm-encode-bpe-o200k-100kb",
    command: nodeBpeEncode100kbCommand,
    category: "throughput",
    bytesProcessed: fixture100kbBytes,
  });
}
if (nodeBpeEncode1mbCommand !== null) {
  benchCases.push({
    name: "node-wasm-encode-bpe-o200k-1mb",
    command: nodeBpeEncode1mbCommand,
    category: "throughput",
    bytesProcessed: fixture1mbBytes,
  });
}

const warmup = fastMode ? 1 : 3;
const minRunsRaw = process.env.TURBOTOKEN_WASM_MIN_RUNS?.trim();
const minRuns = minRunsRaw
  ? Math.max(1, Number.parseInt(minRunsRaw, 10) || 10)
  : fastMode
    ? 5
    : 20;
const maxRunsRaw = process.env.TURBOTOKEN_WASM_MAX_RUNS?.trim();
const maxRuns = maxRunsRaw
  ? Math.max(minRuns, Number.parseInt(maxRunsRaw, 10) || minRuns)
  : fastMode
    ? minRuns
    : null;
const rawHyperfinePath = resolvePath("bench", "results", `bench-wasm-raw-${Date.now()}.json`);

section("WASM startup + throughput");
const hyperfine = resolveHyperfineCommand();
let benchRows: BenchRow[];
let benchTool: "hyperfine" | "manual";
if (hyperfine !== null && commandExists(hyperfine)) {
  const rows = runHyperfineBench(hyperfine, benchCases, warmup, minRuns, maxRuns, rawHyperfinePath);
  if (rows) {
    benchRows = rows;
    benchTool = "hyperfine";
  } else {
    benchRows = runManualBench(benchCases, warmup, minRuns);
    benchTool = "manual";
  }
} else {
  benchRows = runManualBench(benchCases, warmup, minRuns);
  benchTool = "manual";
}

section("WASM memory (RSS)");
const memoryRunsRaw = process.env.TURBOTOKEN_WASM_RAM_RUNS?.trim();
const memoryRuns = memoryRunsRaw
  ? Math.max(1, Number.parseInt(memoryRunsRaw, 10) || 5)
  : fastMode
    ? 2
    : 5;
const memoryCases: Array<{ name: string; command: string }> = [
  { name: "wasm-rss-encode-utf8-bytes-1mb", command: wasmEncode1mbCommand },
  { name: "js-rss-textencoder-u32-1mb", command: jsEncode1mbCommand },
];
if (nodeEncode1mbCommand !== null) {
  memoryCases.push({
    name: "node-wasm-rss-encode-utf8-bytes-1mb",
    command: nodeEncode1mbCommand,
  });
}
if (wasmBpeEncode1mbCommand !== null) {
  memoryCases.push({
    name: "wasm-rss-encode-bpe-o200k-1mb",
    command: wasmBpeEncode1mbCommand,
  });
}
if (nodeBpeEncode1mbCommand !== null) {
  memoryCases.push({
    name: "node-wasm-rss-encode-bpe-o200k-1mb",
    command: nodeBpeEncode1mbCommand,
  });
}
const memoryRows = runMemoryRows(memoryCases, memoryRuns);

const benchRowsWithDerived = benchRows.map((row) => {
  const mbPerSec = row.bytesProcessed == null || row.meanSeconds <= 0
    ? null
    : (row.bytesProcessed / (1024 * 1024)) / row.meanSeconds;
  return {
    ...row,
    startupLatencyMs: row.category === "startup" ? row.meanSeconds * 1000 : null,
    throughputMbPerSec: mbPerSec,
  };
});

const startupRows = benchRowsWithDerived
  .filter((row) => row.category === "startup")
  .map((row) => ({
    name: row.name,
    meanMs: row.startupLatencyMs,
    stddevMs: row.stddevSeconds * 1000,
    minMs: row.minSeconds * 1000,
    maxMs: row.maxSeconds * 1000,
    runs: row.runs,
  }));

const throughputRows = benchRowsWithDerived
  .filter((row) => row.category === "throughput")
  .map((row) => ({
    name: row.name,
    meanSeconds: row.meanSeconds,
    stddevSeconds: row.stddevSeconds,
    bytesProcessed: row.bytesProcessed,
    throughputMbPerSec: row.throughputMbPerSec,
    runs: row.runs,
  }));

const browserRows = [
  {
    name: "browser-wasm-startup-first-encode-hello",
    category: "startup",
    meanMs: null,
    throughputMbPerSec: null,
    status: "not-run",
    reason: "browser benchmark harness is not configured in this local run",
  },
  {
    name: "browser-wasm-encode-utf8-bytes-1mb",
    category: "throughput",
    meanMs: null,
    throughputMbPerSec: null,
    status: "not-run",
    reason: "browser benchmark harness is not configured in this local run",
  },
  {
    name: "browser-wasm-encode-bpe-o200k-1mb",
    category: "throughput",
    meanMs: null,
    throughputMbPerSec: null,
    status: "not-run",
    reason: "browser benchmark harness is not configured in this local run",
  },
];

writeJson(outputPath, {
  generatedAt: new Date().toISOString(),
  status: "ok",
  target: "wasm32-freestanding",
  wasmPath,
  wasmBytes,
  fixtures: {
    english100kbPath: fixture100kb,
    english100kbBytes: fixture100kbBytes,
    english1mbPath: fixture1mb,
    english1mbBytes: fixture1mbBytes,
    rankPayload: rankPayloadInfo
      ? {
        path: rankPayloadInfo.path,
        bytes: rankPayloadInfo.bytes,
        sourceUrl: rankPayloadUrl,
      }
      : null,
  },
  benchmark: {
    tool: benchTool,
    fastMode,
    warmup,
    minRuns,
    maxRuns,
    rawHyperfinePath: benchTool === "hyperfine" ? rawHyperfinePath : null,
    rows: benchRowsWithDerived,
  },
  startup: {
    workload: "time to first encode of 'hello' (cold process)",
    rows: startupRows,
  },
  throughput: {
    workload: "sustained encode throughput",
    units: "MB/s (MiB/s)",
    rows: throughputRows,
  },
  memory: {
    tool: "/usr/bin/time",
    runsPerCommand: memoryRuns,
    workload: "Peak RSS during 1MB encode workloads (UTF-8 byte path and BPE path when rank payload is available)",
    rows: memoryRows,
  },
  browser: {
    rows: browserRows,
  },
  note: "WASM benchmark matrix includes startup latency, throughput MB/s, and RSS-style memory rows for byte-path and optional BPE workloads.",
});

console.log(`Wrote WASM benchmark record: ${outputPath}`);
process.exit(0);
