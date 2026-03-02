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

interface BrowserBenchRow {
  name: string;
  category: "startup" | "throughput";
  meanMs: number | null;
  throughputMbPerSec: number | null;
  runs: number;
  warmup: number;
  status: "ok" | "not-run";
  reason?: string;
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

function envFlag(name: string): boolean {
  const raw = (process.env[name] ?? "").trim().toLowerCase();
  return raw === "1" || raw === "true" || raw === "yes" || raw === "on";
}

function browserFallbackRows(reason: string, runs: number, warmup: number): BrowserBenchRow[] {
  return [
    {
      name: "browser-wasm-startup-first-encode-hello",
      category: "startup",
      meanMs: null,
      throughputMbPerSec: null,
      runs,
      warmup,
      status: "not-run",
      reason,
    },
    {
      name: "browser-wasm-encode-utf8-bytes-1mb",
      category: "throughput",
      meanMs: null,
      throughputMbPerSec: null,
      runs,
      warmup,
      status: "not-run",
      reason,
    },
    {
      name: "browser-wasm-encode-bpe-o200k-1mb",
      category: "throughput",
      meanMs: null,
      throughputMbPerSec: null,
      runs,
      warmup,
      status: "not-run",
      reason,
    },
  ];
}

async function runBrowserRows(params: {
  wasmPath: string;
  fixture1mbPath: string;
  rankPayloadPath: string | null;
  rankPayloadAvailable: boolean;
  fastMode: boolean;
}): Promise<BrowserBenchRow[]> {
  const browserEnable = envFlag("TURBOTOKEN_WASM_BROWSER_ENABLE");
  const browserWarmupRaw = process.env.TURBOTOKEN_WASM_BROWSER_WARMUP?.trim();
  const browserRunsRaw = process.env.TURBOTOKEN_WASM_BROWSER_RUNS?.trim();
  const warmup = browserWarmupRaw
    ? Math.max(0, Number.parseInt(browserWarmupRaw, 10) || 0)
    : params.fastMode
      ? 1
      : 2;
  const runs = browserRunsRaw
    ? Math.max(1, Number.parseInt(browserRunsRaw, 10) || 3)
    : params.fastMode
      ? 3
      : 5;

  if (!browserEnable) {
    return browserFallbackRows("browser harness disabled (set TURBOTOKEN_WASM_BROWSER_ENABLE=1)", runs, warmup);
  }

  let playwrightModule: unknown;
  try {
    playwrightModule = await import("playwright");
  } catch (error) {
    return browserFallbackRows(`playwright not installed: ${String(error)}`, runs, warmup);
  }

  const chromium = (playwrightModule as { chromium?: { launch: (opts?: unknown) => Promise<unknown> } }).chromium;
  if (!chromium) {
    return browserFallbackRows("playwright chromium launcher unavailable", runs, warmup);
  }

  const wasmBytes = new Uint8Array(readFileSync(params.wasmPath));
  const input1mbBytes = new Uint8Array(readFileSync(params.fixture1mbPath));
  const rankBytes = params.rankPayloadAvailable && params.rankPayloadPath
    ? new Uint8Array(readFileSync(params.rankPayloadPath))
    : null;
  if (wasmBytes.byteLength === 0 || input1mbBytes.byteLength === 0) {
    return browserFallbackRows("missing wasm or fixture payload for browser run", runs, warmup);
  }

  let browser: {
    newPage: () => Promise<{
      evaluate: <T, P>(fn: (payload: P) => Promise<T>, payload: P) => Promise<T>;
      close: () => Promise<void>;
    }>;
    close: () => Promise<void>;
  } | null = null;
  try {
    browser = await (chromium.launch({
      headless: true,
    }) as Promise<typeof browser>);
  } catch (error) {
    return browserFallbackRows(`failed to launch headless chromium: ${String(error)}`, runs, warmup);
  }

  try {
    const page = await browser.newPage();
    const result = await page.evaluate(
      async (payload: {
        wasmBytes: number[];
        inputBytes: number[];
        rankBytes: number[] | null;
        runs: number;
        warmup: number;
      }) => {
        const wasmBytes = new Uint8Array(payload.wasmBytes);
        const inputBytes = new Uint8Array(payload.inputBytes);
        const rankBytes = payload.rankBytes ? new Uint8Array(payload.rankBytes) : null;
        const hello = new TextEncoder().encode("hello");
        const bytesToMiB = (bytes: number, ms: number): number | null => {
          if (!Number.isFinite(ms) || ms <= 0) {
            return null;
          }
          return (bytes / (1024 * 1024)) / (ms / 1000);
        };
        const instantiate = async () => {
          const { instance } = await WebAssembly.instantiate(wasmBytes, {});
          const exports = instance.exports as {
            memory: WebAssembly.Memory;
            turbotoken_wasm_alloc: (size: number) => number;
            turbotoken_wasm_free: (ptr: number, size: number) => void;
            turbotoken_encode_utf8_bytes: (
              textPtr: number,
              textLen: number,
              outTokensPtr: number,
              outCap: number,
            ) => number;
            turbotoken_encode_bpe_from_ranks: (
              rankPtr: number,
              rankLen: number,
              textPtr: number,
              textLen: number,
              outTokensPtr: number,
              outCap: number,
            ) => number;
            turbotoken_decode_utf8_bytes: (
              tokensPtr: number,
              tokenLen: number,
              outBytesPtr: number,
              outCap: number,
            ) => number;
            turbotoken_decode_bpe_from_ranks: (
              rankPtr: number,
              rankLen: number,
              tokensPtr: number,
              tokenLen: number,
              outBytesPtr: number,
              outCap: number,
            ) => number;
          };
          if (typeof exports.turbotoken_wasm_alloc !== "function" || typeof exports.turbotoken_encode_utf8_bytes !== "function") {
            throw new Error("required wasm exports are missing");
          }
          if (typeof exports.turbotoken_decode_utf8_bytes !== "function") {
            throw new Error("required wasm decode export is missing");
          }
          return exports;
        };
        const encodeUtf8Once = (exports: {
          memory: WebAssembly.Memory;
          turbotoken_wasm_alloc: (size: number) => number;
          turbotoken_wasm_free: (ptr: number, size: number) => void;
          turbotoken_encode_utf8_bytes: (textPtr: number, textLen: number, outTokensPtr: number, outCap: number) => number;
        }, textBytes: Uint8Array): void => {
          const textPtr = exports.turbotoken_wasm_alloc(textBytes.byteLength);
          if (textPtr === 0) {
            throw new Error("wasm alloc failed for utf8 text");
          }
          const outBytes = textBytes.byteLength * 4;
          const outPtr = exports.turbotoken_wasm_alloc(outBytes);
          if (outPtr === 0) {
            exports.turbotoken_wasm_free(textPtr, textBytes.byteLength);
            throw new Error("wasm alloc failed for utf8 output");
          }
          try {
            new Uint8Array(exports.memory.buffer).set(textBytes, textPtr);
            const written = exports.turbotoken_encode_utf8_bytes(textPtr, textBytes.byteLength, outPtr, textBytes.byteLength);
            if (written < 0) {
              throw new Error("utf8 encode failed");
            }
          } finally {
            exports.turbotoken_wasm_free(outPtr, outBytes);
            exports.turbotoken_wasm_free(textPtr, textBytes.byteLength);
          }
        };
        const encodeBpeOnce = (exports: {
          memory: WebAssembly.Memory;
          turbotoken_wasm_alloc: (size: number) => number;
          turbotoken_wasm_free: (ptr: number, size: number) => void;
          turbotoken_encode_bpe_from_ranks: (
            rankPtr: number,
            rankLen: number,
            textPtr: number,
            textLen: number,
            outTokensPtr: number,
            outCap: number,
          ) => number;
        }, ranks: Uint8Array, textBytes: Uint8Array): void => {
          const rankPtr = exports.turbotoken_wasm_alloc(ranks.byteLength);
          const textPtr = exports.turbotoken_wasm_alloc(textBytes.byteLength);
          if (rankPtr === 0 || textPtr === 0) {
            if (rankPtr !== 0) {
              exports.turbotoken_wasm_free(rankPtr, ranks.byteLength);
            }
            if (textPtr !== 0) {
              exports.turbotoken_wasm_free(textPtr, textBytes.byteLength);
            }
            throw new Error("wasm alloc failed for bpe inputs");
          }
          const outBytes = textBytes.byteLength * 4;
          const outPtr = exports.turbotoken_wasm_alloc(outBytes);
          if (outPtr === 0) {
            exports.turbotoken_wasm_free(rankPtr, ranks.byteLength);
            exports.turbotoken_wasm_free(textPtr, textBytes.byteLength);
            throw new Error("wasm alloc failed for bpe output");
          }
          try {
            const heap = new Uint8Array(exports.memory.buffer);
            heap.set(ranks, rankPtr);
            heap.set(textBytes, textPtr);
            const written = exports.turbotoken_encode_bpe_from_ranks(
              rankPtr,
              ranks.byteLength,
              textPtr,
              textBytes.byteLength,
              outPtr,
              textBytes.byteLength,
            );
            if (written < 0) {
              throw new Error("bpe encode failed");
            }
          } finally {
            exports.turbotoken_wasm_free(outPtr, outBytes);
            exports.turbotoken_wasm_free(textPtr, textBytes.byteLength);
            exports.turbotoken_wasm_free(rankPtr, ranks.byteLength);
          }
        };
        const readU32List = (memory: WebAssembly.Memory, ptr: number, len: number): Uint32Array => {
          if (len <= 0) {
            return new Uint32Array(0);
          }
          if ((ptr & 3) === 0) {
            return new Uint32Array(memory.buffer.slice(ptr, ptr + (len * 4)));
          }
          const out = new Uint32Array(len);
          const dv = new DataView(memory.buffer);
          for (let i = 0; i < len; i += 1) {
            out[i] = dv.getUint32(ptr + (i * 4), true);
          }
          return out;
        };
        const writeU32List = (memory: WebAssembly.Memory, ptr: number, values: Uint32Array): void => {
          if (values.length === 0) {
            return;
          }
          if ((ptr & 3) === 0) {
            new Uint32Array(memory.buffer, ptr, values.length).set(values);
            return;
          }
          const dv = new DataView(memory.buffer);
          for (let i = 0; i < values.length; i += 1) {
            dv.setUint32(ptr + (i * 4), values[i], true);
          }
        };
        const encodeUtf8Tokens = (exports: {
          memory: WebAssembly.Memory;
          turbotoken_wasm_alloc: (size: number) => number;
          turbotoken_wasm_free: (ptr: number, size: number) => void;
          turbotoken_encode_utf8_bytes: (textPtr: number, textLen: number, outTokensPtr: number, outCap: number) => number;
        }, textBytes: Uint8Array): Uint32Array => {
          const textPtr = exports.turbotoken_wasm_alloc(textBytes.byteLength);
          if (textPtr === 0) {
            throw new Error("wasm alloc failed for utf8 parity text");
          }
          const outBytes = textBytes.byteLength * 4;
          const outPtr = exports.turbotoken_wasm_alloc(outBytes);
          if (outPtr === 0) {
            exports.turbotoken_wasm_free(textPtr, textBytes.byteLength);
            throw new Error("wasm alloc failed for utf8 parity output");
          }
          try {
            new Uint8Array(exports.memory.buffer).set(textBytes, textPtr);
            const written = exports.turbotoken_encode_utf8_bytes(textPtr, textBytes.byteLength, outPtr, textBytes.byteLength);
            if (written < 0) {
              throw new Error("utf8 parity encode failed");
            }
            return readU32List(exports.memory, outPtr, written);
          } finally {
            exports.turbotoken_wasm_free(outPtr, outBytes);
            exports.turbotoken_wasm_free(textPtr, textBytes.byteLength);
          }
        };
        const encodeBpeTokens = (exports: {
          memory: WebAssembly.Memory;
          turbotoken_wasm_alloc: (size: number) => number;
          turbotoken_wasm_free: (ptr: number, size: number) => void;
          turbotoken_encode_bpe_from_ranks: (
            rankPtr: number,
            rankLen: number,
            textPtr: number,
            textLen: number,
            outTokensPtr: number,
            outCap: number,
          ) => number;
        }, ranks: Uint8Array, textBytes: Uint8Array): Uint32Array => {
          const rankPtr = exports.turbotoken_wasm_alloc(ranks.byteLength);
          const textPtr = exports.turbotoken_wasm_alloc(textBytes.byteLength);
          if (rankPtr === 0 || textPtr === 0) {
            if (rankPtr !== 0) {
              exports.turbotoken_wasm_free(rankPtr, ranks.byteLength);
            }
            if (textPtr !== 0) {
              exports.turbotoken_wasm_free(textPtr, textBytes.byteLength);
            }
            throw new Error("wasm alloc failed for bpe parity inputs");
          }
          const outBytes = textBytes.byteLength * 4;
          const outPtr = exports.turbotoken_wasm_alloc(outBytes);
          if (outPtr === 0) {
            exports.turbotoken_wasm_free(rankPtr, ranks.byteLength);
            exports.turbotoken_wasm_free(textPtr, textBytes.byteLength);
            throw new Error("wasm alloc failed for bpe parity output");
          }
          try {
            const heap = new Uint8Array(exports.memory.buffer);
            heap.set(ranks, rankPtr);
            heap.set(textBytes, textPtr);
            const written = exports.turbotoken_encode_bpe_from_ranks(
              rankPtr,
              ranks.byteLength,
              textPtr,
              textBytes.byteLength,
              outPtr,
              textBytes.byteLength,
            );
            if (written < 0) {
              throw new Error("bpe parity encode failed");
            }
            return readU32List(exports.memory, outPtr, written);
          } finally {
            exports.turbotoken_wasm_free(outPtr, outBytes);
            exports.turbotoken_wasm_free(textPtr, textBytes.byteLength);
            exports.turbotoken_wasm_free(rankPtr, ranks.byteLength);
          }
        };
        const decodeUtf8Tokens = (exports: {
          memory: WebAssembly.Memory;
          turbotoken_wasm_alloc: (size: number) => number;
          turbotoken_wasm_free: (ptr: number, size: number) => void;
          turbotoken_decode_utf8_bytes: (tokensPtr: number, tokenLen: number, outBytesPtr: number, outCap: number) => number;
        }, tokens: Uint32Array): Uint8Array => {
          if (tokens.length === 0) {
            return new Uint8Array(0);
          }
          const tokenBytes = tokens.length * 4;
          const tokenPtr = exports.turbotoken_wasm_alloc(tokenBytes);
          if (tokenPtr === 0) {
            throw new Error("wasm alloc failed for utf8 parity token input");
          }
          writeU32List(exports.memory, tokenPtr, tokens);
          try {
            const needed = exports.turbotoken_decode_utf8_bytes(tokenPtr, tokens.length, 0, 0);
            if (needed < 0) {
              throw new Error("utf8 parity decode size failed");
            }
            if (needed === 0) {
              return new Uint8Array(0);
            }
            const outPtr = exports.turbotoken_wasm_alloc(needed);
            if (outPtr === 0) {
              throw new Error("wasm alloc failed for utf8 parity decode output");
            }
            try {
              const written = exports.turbotoken_decode_utf8_bytes(tokenPtr, tokens.length, outPtr, needed);
              if (written < 0) {
                throw new Error("utf8 parity decode failed");
              }
              return new Uint8Array(exports.memory.buffer.slice(outPtr, outPtr + written));
            } finally {
              exports.turbotoken_wasm_free(outPtr, needed);
            }
          } finally {
            exports.turbotoken_wasm_free(tokenPtr, tokenBytes);
          }
        };
        const decodeBpeTokens = (exports: {
          memory: WebAssembly.Memory;
          turbotoken_wasm_alloc: (size: number) => number;
          turbotoken_wasm_free: (ptr: number, size: number) => void;
          turbotoken_decode_bpe_from_ranks: (
            rankPtr: number,
            rankLen: number,
            tokensPtr: number,
            tokenLen: number,
            outBytesPtr: number,
            outCap: number,
          ) => number;
        }, ranks: Uint8Array, tokens: Uint32Array): Uint8Array => {
          const rankPtr = exports.turbotoken_wasm_alloc(ranks.byteLength);
          if (rankPtr === 0) {
            throw new Error("wasm alloc failed for bpe parity rank input");
          }
          new Uint8Array(exports.memory.buffer).set(ranks, rankPtr);
          try {
            const tokenBytes = tokens.length * 4;
            const tokenPtr = exports.turbotoken_wasm_alloc(tokenBytes);
            if (tokenPtr === 0 && tokenBytes > 0) {
              throw new Error("wasm alloc failed for bpe parity token input");
            }
            if (tokenBytes > 0) {
              writeU32List(exports.memory, tokenPtr, tokens);
            }
            try {
              const needed = exports.turbotoken_decode_bpe_from_ranks(
                rankPtr,
                ranks.byteLength,
                tokenPtr,
                tokens.length,
                0,
                0,
              );
              if (needed < 0) {
                throw new Error("bpe parity decode size failed");
              }
              if (needed === 0) {
                return new Uint8Array(0);
              }
              const outPtr = exports.turbotoken_wasm_alloc(needed);
              if (outPtr === 0) {
                throw new Error("wasm alloc failed for bpe parity decode output");
              }
              try {
                const written = exports.turbotoken_decode_bpe_from_ranks(
                  rankPtr,
                  ranks.byteLength,
                  tokenPtr,
                  tokens.length,
                  outPtr,
                  needed,
                );
                if (written < 0) {
                  throw new Error("bpe parity decode failed");
                }
                return new Uint8Array(exports.memory.buffer.slice(outPtr, outPtr + written));
              } finally {
                exports.turbotoken_wasm_free(outPtr, needed);
              }
            } finally {
              if (tokenBytes > 0) {
                exports.turbotoken_wasm_free(tokenPtr, tokenBytes);
              }
            }
          } finally {
            exports.turbotoken_wasm_free(rankPtr, ranks.byteLength);
          }
        };
        const assertBytesEqual = (actual: Uint8Array, expected: Uint8Array, label: string): void => {
          if (actual.byteLength !== expected.byteLength) {
            throw new Error(`${label} length mismatch (${actual.byteLength} vs ${expected.byteLength})`);
          }
          for (let i = 0; i < actual.byteLength; i += 1) {
            if (actual[i] !== expected[i]) {
              throw new Error(`${label} mismatch at byte ${i}`);
            }
          }
        };
        const measureMs = async (fn: () => Promise<void>, warmup: number, runs: number): Promise<number> => {
          for (let i = 0; i < warmup; i += 1) {
            await fn();
          }
          const start = performance.now();
          for (let i = 0; i < runs; i += 1) {
            await fn();
          }
          return (performance.now() - start) / runs;
        };

        // Browser parity checks: verify encode/decode invariants before timing.
        const paritySample = inputBytes.subarray(0, Math.min(inputBytes.byteLength, 64 * 1024));
        const parityExports = await instantiate();
        const helloUtf8Tokens = encodeUtf8Tokens(parityExports, hello);
        if (helloUtf8Tokens.length !== hello.byteLength) {
          throw new Error("utf8 parity failed for hello length");
        }
        const decodedHelloUtf8 = decodeUtf8Tokens(parityExports, helloUtf8Tokens);
        assertBytesEqual(decodedHelloUtf8, hello, "utf8 hello decode");
        const sampleUtf8Tokens = encodeUtf8Tokens(parityExports, paritySample);
        if (sampleUtf8Tokens.length !== paritySample.byteLength) {
          throw new Error("utf8 parity failed for sample length");
        }
        const decodedSampleUtf8 = decodeUtf8Tokens(parityExports, sampleUtf8Tokens);
        assertBytesEqual(decodedSampleUtf8, paritySample, "utf8 sample decode");
        for (let i = 0; i < Math.min(sampleUtf8Tokens.length, paritySample.byteLength); i += 1) {
          if (sampleUtf8Tokens[i] !== paritySample[i]) {
            throw new Error(`utf8 sample token mismatch at index ${i}`);
          }
        }

        let bpeParityChecked = false;
        if (rankBytes && rankBytes.byteLength > 0) {
          const helloBpeTokens = encodeBpeTokens(parityExports, rankBytes, hello);
          const helloBpeTokensRepeat = encodeBpeTokens(parityExports, rankBytes, hello);
          if (helloBpeTokens.length !== helloBpeTokensRepeat.length) {
            throw new Error("bpe parity failed for hello deterministic length");
          }
          for (let i = 0; i < helloBpeTokens.length; i += 1) {
            if (helloBpeTokens[i] !== helloBpeTokensRepeat[i]) {
              throw new Error(`bpe parity failed for hello deterministic token at ${i}`);
            }
          }
          const decodedHelloBpe = decodeBpeTokens(parityExports, rankBytes, helloBpeTokens);
          assertBytesEqual(decodedHelloBpe, hello, "bpe hello decode");
          const sampleBpeTokens = encodeBpeTokens(parityExports, rankBytes, paritySample);
          const decodedSampleBpe = decodeBpeTokens(parityExports, rankBytes, sampleBpeTokens);
          assertBytesEqual(decodedSampleBpe, paritySample, "bpe sample decode");
          bpeParityChecked = true;
        }

        const startupMs = await measureMs(async () => {
          const exports = await instantiate();
          encodeUtf8Once(exports, hello);
        }, payload.warmup, payload.runs);

        const utf8Exports = await instantiate();
        const utf8Ms = await measureMs(async () => {
          encodeUtf8Once(utf8Exports, inputBytes);
        }, payload.warmup, payload.runs);

        let bpeMs: number | null = null;
        if (rankBytes && rankBytes.byteLength > 0) {
          const bpeExports = await instantiate();
          bpeMs = await measureMs(async () => {
            encodeBpeOnce(bpeExports, rankBytes, inputBytes);
          }, payload.warmup, payload.runs);
        }

        return {
          startupMs,
          utf8Ms,
          utf8MiBPerSec: bytesToMiB(inputBytes.byteLength, utf8Ms),
          bpeMs,
          bpeMiBPerSec: bpeMs == null ? null : bytesToMiB(inputBytes.byteLength, bpeMs),
          parity: {
            utf8RoundTripChecked: true,
            utf8IdentityChecked: true,
            bpeRoundTripChecked: bpeParityChecked,
          },
        };
      },
      {
        wasmBytes: Array.from(wasmBytes),
        inputBytes: Array.from(input1mbBytes),
        rankBytes: rankBytes ? Array.from(rankBytes) : null,
        runs,
        warmup,
      },
    );
    await page.close();

    const rows: BrowserBenchRow[] = [
      {
        name: "browser-wasm-startup-first-encode-hello",
        category: "startup",
        meanMs: typeof result.startupMs === "number" ? result.startupMs : null,
        throughputMbPerSec: null,
        runs,
        warmup,
        status: "ok",
      },
      {
        name: "browser-wasm-encode-utf8-bytes-1mb",
        category: "throughput",
        meanMs: typeof result.utf8Ms === "number" ? result.utf8Ms : null,
        throughputMbPerSec: typeof result.utf8MiBPerSec === "number" ? result.utf8MiBPerSec : null,
        runs,
        warmup,
        status: "ok",
      },
      {
        name: "browser-wasm-encode-bpe-o200k-1mb",
        category: "throughput",
        meanMs: typeof result.bpeMs === "number" ? result.bpeMs : null,
        throughputMbPerSec: typeof result.bpeMiBPerSec === "number" ? result.bpeMiBPerSec : null,
        runs,
        warmup,
        status: result.bpeMs == null ? "not-run" : "ok",
        reason: result.bpeMs == null ? "rank payload unavailable for browser BPE run" : undefined,
      },
    ];
    return rows;
  } catch (error) {
    return browserFallbackRows(`browser benchmark failed: ${String(error)}`, runs, warmup);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
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

const browserRows = await runBrowserRows({
  wasmPath,
  fixture1mbPath: fixture1mb,
  rankPayloadPath: rankPayloadInfo?.path ?? null,
  rankPayloadAvailable: rankPayloadInfo !== null,
  fastMode,
});

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
    enabled: envFlag("TURBOTOKEN_WASM_BROWSER_ENABLE"),
    rows: browserRows,
  },
  note: "WASM benchmark matrix includes startup latency, throughput MB/s, and RSS-style memory rows for byte-path and optional BPE workloads.",
});

console.log(`Wrote WASM benchmark record: ${outputPath}`);
process.exit(0);
