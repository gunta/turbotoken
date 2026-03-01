#!/usr/bin/env bun
import { performance } from "node:perf_hooks";
import { resolve } from "node:path";
import { existsSync } from "node:fs";
import {
  dateTag,
  ensureDir,
  resolvePath,
  runCommand,
  runShell,
  section,
  withBenchmarkLock,
  writeJson,
} from "./_lib";

export interface BenchCommand {
  name: string;
  command: string;
}

export interface BenchOptions {
  name: string;
  commands: BenchCommand[];
  warmup?: number;
  minRuns?: number;
  metadata?: Record<string, unknown>;
}

interface ManualResult {
  command: string;
  commandName: string;
  runs: number;
  warmup: number;
  seconds: number[];
  meanSeconds: number;
}

function mean(values: number[]): number {
  if (values.length === 0) {
    return 0;
  }
  return values.reduce((acc, value) => acc + value, 0) / values.length;
}

function formatMillis(seconds: number): string {
  return `${(seconds * 1000).toFixed(3)} ms`;
}

function runManualBench(commands: BenchCommand[], warmup: number, runs: number): ManualResult[] {
  const results: ManualResult[] = [];

  for (const item of commands) {
    section(`Manual benchmark: ${item.name}`);

    for (let i = 0; i < warmup; i += 1) {
      runShell(item.command);
    }

    const seconds: number[] = [];
    for (let i = 0; i < runs; i += 1) {
      const start = performance.now();
      runShell(item.command);
      seconds.push((performance.now() - start) / 1000);
    }

    const avg = mean(seconds);
    console.log(`mean: ${formatMillis(avg)} (${runs} runs)`);

    results.push({
      command: item.command,
      commandName: item.name,
      runs,
      warmup,
      seconds,
      meanSeconds: avg,
    });
  }

  return results;
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

function envFlag(name: string): boolean {
  const raw = (process.env[name] ?? "").trim().toLowerCase();
  return raw === "1" || raw === "true" || raw === "yes" || raw === "on";
}

function benchRunScale(): number {
  const raw = (process.env.TURBOTOKEN_BENCH_HYPERFINE_RUN_SCALE ?? "").trim();
  if (raw.length > 0) {
    const parsed = Number.parseFloat(raw);
    if (Number.isFinite(parsed) && parsed > 0) {
      return parsed;
    }
  }
  if (envFlag("TURBOTOKEN_BENCH_FAST")) {
    return 0.25;
  }
  return 1;
}

function benchMaxRuns(minRuns: number): number | null {
  const raw = (process.env.TURBOTOKEN_BENCH_HYPERFINE_MAX_RUNS ?? "").trim();
  if (raw.length > 0) {
    const parsed = Number.parseInt(raw, 10);
    if (Number.isFinite(parsed) && parsed > 0) {
      return Math.max(minRuns, parsed);
    }
  }
  if (envFlag("TURBOTOKEN_BENCH_FAST")) {
    return minRuns;
  }
  return null;
}

export function runBench(options: BenchOptions): number {
  return withBenchmarkLock(options.name, () => {
    const configuredWarmup = options.warmup ?? 3;
    const configuredMinRuns = options.minRuns ?? 10;
    const runScale = benchRunScale();
    const warmup = Math.max(0, Math.floor(configuredWarmup * runScale));
    const minRuns = Math.max(1, Math.ceil(configuredMinRuns * runScale));
    const maxRuns = benchMaxRuns(minRuns);

    if (options.commands.length === 0) {
      throw new Error("runBench requires at least one command");
    }

    const resultsDir = resolvePath("bench", "results");
    ensureDir(resultsDir);

    const taggedName = `${options.name}-${dateTag()}`;
    const jsonPath = resolve(resultsDir, `${taggedName}.json`);

    const hyperfine = resolveHyperfineCommand();
    if (hyperfine !== null) {
      section(`Hyperfine: ${options.name}`);

      const args = [
        "--warmup",
        String(warmup),
        "--min-runs",
        String(minRuns),
        "--export-json",
        jsonPath,
      ];
      if (maxRuns != null) {
        args.push("--max-runs", String(maxRuns));
      }

      for (const item of options.commands) {
        args.push("--command-name", item.name, item.command);
      }

      const result = runCommand(hyperfine, args, { allowFailure: true });
      const output = [result.stdout.trim(), result.stderr.trim()].filter(Boolean).join("\n");
      if (output.length > 0) {
        console.log(output);
      }

      if (result.code === 0) {
        if (options.metadata) {
          const metaPath = resolve(resultsDir, `${taggedName}.meta.json`);
          writeJson(metaPath, {
            ...options.metadata,
            benchmarkTuning: {
              runScale,
            configuredWarmup,
            configuredMinRuns,
            effectiveWarmup: warmup,
            effectiveMinRuns: minRuns,
            effectiveMaxRuns: maxRuns,
          },
        });
        }
        console.log(`Wrote Hyperfine JSON: ${jsonPath}`);
        return 0;
      }

      console.warn("hyperfine failed, falling back to manual timing");
    } else {
      console.warn("hyperfine not found, falling back to manual timing");
    }

    const manualResults = runManualBench(options.commands, warmup, minRuns);
    writeJson(jsonPath, {
      tool: "manual",
      generatedAt: new Date().toISOString(),
      name: options.name,
      metadata: {
        ...(options.metadata ?? {}),
        benchmarkTuning: {
          runScale,
          configuredWarmup,
          configuredMinRuns,
          effectiveWarmup: warmup,
          effectiveMinRuns: minRuns,
          effectiveMaxRuns: maxRuns,
        },
      },
      results: manualResults,
    });
    console.log(`Wrote manual benchmark JSON: ${jsonPath}`);
    return 0;
  });
}
