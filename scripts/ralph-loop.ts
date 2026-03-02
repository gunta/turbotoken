#!/usr/bin/env bun
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import {
  acquireBenchmarkLock,
  dateTag,
  ensureDir,
  resolvePath,
  runCommand,
  section,
  writeJson,
} from "./_lib";

type PhaseName = "governance" | "training" | "metal" | "wasm" | "x86" | "competitors";

interface LoopTask {
  id: string;
  phase: PhaseName;
  command: string;
  args: string[];
  timeoutMs?: number;
  env?: Record<string, string>;
}

interface TaskRunRecord {
  id: string;
  phase: PhaseName;
  command: string;
  args: string[];
  startedAt: string;
  endedAt: string;
  durationMs: number;
  exitCode: number;
  ok: boolean;
  stdoutTail: string;
  stderrTail: string;
}

interface CycleRecord {
  index: number;
  startedAt: string;
  endedAt?: string;
  durationMs?: number;
  ok: boolean;
  tasks: TaskRunRecord[];
}

interface LoopState {
  version: number;
  id: string;
  createdAt: string;
  updatedAt: string;
  startedAt: string;
  runConfig: {
    quick: boolean;
    phases: PhaseName[];
    maxCycles: number | null;
    hours: number | null;
    sleepSeconds: number;
    stopOnFailure: boolean;
    scorecardEachCycle: boolean;
    fullGovernanceEvery: number;
    competitorsEvery: number;
  };
  cycles: CycleRecord[];
  totals: {
    tasks: number;
    failedTasks: number;
    succeededTasks: number;
  };
}

interface CliConfig {
  quick: boolean;
  phases: PhaseName[];
  maxCycles: number | null;
  hours: number | null;
  sleepSeconds: number;
  stopOnFailure: boolean;
  scorecardEachCycle: boolean;
  fullGovernanceEvery: number;
  competitorsEvery: number;
  statePath: string;
  reportPath: string;
  fresh: boolean;
}

const ALL_PHASES: PhaseName[] = ["governance", "training", "metal", "wasm", "x86", "competitors"];
const DEFAULT_PHASES: PhaseName[] = ["training", "metal", "wasm", "x86", "governance"];
const RALPH_LOOP_ENABLE_ENV = "TURBOTOKEN_RALPH_LOOP_ENABLE";

function assertLoopEnabled(): void {
  const raw = (process.env[RALPH_LOOP_ENABLE_ENV] ?? "").trim().toLowerCase();
  if (raw === "1" || raw === "true" || raw === "yes") {
    return;
  }
  console.error(
    `Ralph loop is temporarily disabled by default. Set ${RALPH_LOOP_ENABLE_ENV}=1 to run it intentionally.`,
  );
  process.exit(2);
}

function parsePositiveInt(raw: string | null): number | null {
  if (!raw || raw.trim().length === 0) {
    return null;
  }
  const value = Number.parseInt(raw, 10);
  if (!Number.isFinite(value) || value <= 0) {
    return null;
  }
  return value;
}

function parsePositiveFloat(raw: string | null): number | null {
  if (!raw || raw.trim().length === 0) {
    return null;
  }
  const value = Number.parseFloat(raw);
  if (!Number.isFinite(value) || value <= 0) {
    return null;
  }
  return value;
}

function parseArgValue(argv: string[], key: string): string | null {
  const prefix = `${key}=`;
  const arg = argv.find((item) => item.startsWith(prefix));
  if (!arg) {
    return null;
  }
  const raw = arg.slice(prefix.length).trim();
  return raw.length > 0 ? raw : null;
}

function parsePhases(raw: string | null): PhaseName[] {
  if (!raw) {
    return [...DEFAULT_PHASES];
  }
  const values = raw
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter((value) => value.length > 0);
  if (values.length === 0) {
    return [...DEFAULT_PHASES];
  }
  const parsed: PhaseName[] = [];
  for (const value of values) {
    if (!ALL_PHASES.includes(value as PhaseName)) {
      throw new Error(`invalid phase ${JSON.stringify(value)} (expected one of ${ALL_PHASES.join(", ")})`);
    }
    parsed.push(value as PhaseName);
  }
  return parsed;
}

function parseCli(argv: string[]): CliConfig {
  const quick = argv.includes("--quick");
  const stopOnFailure = argv.includes("--stop-on-failure");
  const noScorecard = argv.includes("--no-scorecard");
  const fresh = argv.includes("--fresh");
  const maxCycles = parsePositiveInt(parseArgValue(argv, "--max-cycles"));
  const hours = parsePositiveFloat(parseArgValue(argv, "--hours"));
  const sleepSeconds = parsePositiveInt(parseArgValue(argv, "--sleep-seconds")) ?? 0;
  const fullGovernanceEvery = parsePositiveInt(parseArgValue(argv, "--full-governance-every")) ?? (quick ? 3 : 2);
  const competitorsEvery = parsePositiveInt(parseArgValue(argv, "--competitors-every")) ?? (quick ? 4 : 3);
  const phases = parsePhases(parseArgValue(argv, "--phases"));
  const statePath =
    parseArgValue(argv, "--state") ?? resolvePath("bench", "results", "ralph-loop-state.json");
  const reportPath =
    parseArgValue(argv, "--report") ?? resolvePath("bench", "charts", "ralph-loop.md");

  return {
    quick,
    phases,
    maxCycles,
    hours,
    sleepSeconds,
    stopOnFailure,
    scorecardEachCycle: !noScorecard,
    fullGovernanceEvery,
    competitorsEvery,
    statePath: resolvePath(statePath),
    reportPath: resolvePath(reportPath),
    fresh,
  };
}

function shortTail(input: string, maxChars = 1600): string {
  const trimmed = input.trim();
  if (trimmed.length <= maxChars) {
    return trimmed;
  }
  return trimmed.slice(trimmed.length - maxChars);
}

function buildTasks(config: CliConfig, cycleIndex: number): LoopTask[] {
  const commonBenchEnv: Record<string, string> = {
    TURBOTOKEN_BENCH_INCLUDE_CUDA: "0",
    TURBOTOKEN_BENCH_SPEED: config.quick ? "fast" : "full",
    // Governance/gate checks must use full-fidelity artifacts, even in quick loops.
    TURBOTOKEN_CI_ARTIFACT_SPEED: "full",
  };
  const gpuQuickEnv: Record<string, string> = {
    TURBOTOKEN_GPU_CROSSOVER_QUICK: "1",
    TURBOTOKEN_GPU_MEMORY_RUNS: "1",
    TURBOTOKEN_GPU_MEMORY_ROUTE_BYTES: "262144",
  };

  const tasks: LoopTask[] = [];
  const include = (phase: PhaseName): boolean => config.phases.includes(phase);
  const runFullGovernance = cycleIndex % config.fullGovernanceEvery === 0;
  const runCompetitorsSweep = cycleIndex % config.competitorsEvery === 0;

  if (include("governance")) {
    if (config.quick) {
      tasks.push(
        {
          id: "governance-cpu-norun",
          phase: "governance",
          command: "bun",
          args: [
            "run",
            "scripts/ci-benchmark.ts",
            "--mode=cpu",
            "--profile=linux-x86_64-cpu",
            "--no-run",
            "--artifact-speed=full",
          ],
          timeoutMs: 15 * 60 * 1000,
          env: commonBenchEnv,
        },
        {
          id: "governance-gpu-norun",
          phase: "governance",
          command: "bun",
          args: [
            "run",
            "scripts/ci-benchmark.ts",
            "--mode=gpu",
            "--profile=macos-arm64-metal",
            "--no-run",
            "--artifact-speed=full",
          ],
          timeoutMs: 15 * 60 * 1000,
          env: { ...commonBenchEnv, ...gpuQuickEnv },
        },
      );
    } else if (runFullGovernance) {
      tasks.push(
        {
          id: "governance-cpu-full",
          phase: "governance",
          command: "bun",
          args: ["run", "scripts/ci-benchmark.ts", "--mode=cpu", "--profile=linux-x86_64-cpu"],
          timeoutMs: 75 * 60 * 1000,
          env: commonBenchEnv,
        },
        {
          id: "governance-gpu-full",
          phase: "governance",
          command: "bun",
          args: ["run", "scripts/ci-benchmark.ts", "--mode=gpu", "--profile=macos-arm64-metal"],
          timeoutMs: 75 * 60 * 1000,
          env: { ...commonBenchEnv, ...gpuQuickEnv },
        },
      );
    } else {
      tasks.push(
        {
          id: "governance-cpu-norun",
          phase: "governance",
          command: "bun",
          args: [
            "run",
            "scripts/ci-benchmark.ts",
            "--mode=cpu",
            "--profile=linux-x86_64-cpu",
            "--no-run",
            "--artifact-speed=full",
          ],
          timeoutMs: 15 * 60 * 1000,
          env: commonBenchEnv,
        },
        {
          id: "governance-gpu-norun",
          phase: "governance",
          command: "bun",
          args: [
            "run",
            "scripts/ci-benchmark.ts",
            "--mode=gpu",
            "--profile=macos-arm64-metal",
            "--no-run",
            "--artifact-speed=full",
          ],
          timeoutMs: 15 * 60 * 1000,
          env: { ...commonBenchEnv, ...gpuQuickEnv },
        },
      );
    }
  }

  if (include("training")) {
    tasks.push(
      {
        id: "training-bench",
        phase: "training",
        command: "bun",
        args: ["run", "scripts/bench-training.ts"],
        timeoutMs: 30 * 60 * 1000,
        env: commonBenchEnv,
      },
      {
        id: "training-gates-norun",
        phase: "training",
        command: "bun",
        args: [
          "run",
          "scripts/ci-benchmark.ts",
          "--mode=cpu",
          "--profile=linux-x86_64-cpu",
          "--no-run",
          "--artifact-speed=full",
        ],
        timeoutMs: 10 * 60 * 1000,
        env: commonBenchEnv,
      },
    );
  }

  if (include("metal")) {
    tasks.push(
      {
        id: "metal-memory",
        phase: "metal",
        command: "bun",
        args: ["run", "scripts/bench-gpu-memory.ts"],
        timeoutMs: 30 * 60 * 1000,
        env: { ...commonBenchEnv, ...gpuQuickEnv },
      },
      {
        id: "metal-crossover",
        phase: "metal",
        command: "bun",
        args: ["run", "scripts/bench-gpu-crossover.ts"],
        timeoutMs: 45 * 60 * 1000,
        env: { ...commonBenchEnv, ...gpuQuickEnv },
      },
      {
        id: "metal-direct-ab",
        phase: "metal",
        command: "bun",
        args: ["run", "scripts/bench-gpu-bpe-direct.ts"],
        timeoutMs: 50 * 60 * 1000,
        env: { ...commonBenchEnv, ...gpuQuickEnv },
      },
      {
        id: "metal-overlap",
        phase: "metal",
        command: "bun",
        args: ["run", "scripts/bench-gpu-overlap.ts"],
        timeoutMs: 35 * 60 * 1000,
        env: { ...commonBenchEnv, ...gpuQuickEnv },
      },
      {
        id: "metal-gates-norun",
        phase: "metal",
        command: "bun",
        args: [
          "run",
          "scripts/ci-benchmark.ts",
          "--mode=gpu",
          "--profile=macos-arm64-metal",
          "--no-run",
          "--artifact-speed=full",
        ],
        timeoutMs: 10 * 60 * 1000,
        env: { ...commonBenchEnv, ...gpuQuickEnv },
      },
    );
  }

  if (include("wasm")) {
    tasks.push(
      {
        id: "wasm-build",
        phase: "wasm",
        command: "zig",
        args: ["build", "wasm", "-Doptimize=ReleaseSmall"],
        timeoutMs: 20 * 60 * 1000,
      },
      {
        id: "wasm-bench",
        phase: "wasm",
        command: "bun",
        args: ["run", "scripts/bench-wasm.ts"],
        timeoutMs: 30 * 60 * 1000,
        env: commonBenchEnv,
      },
    );
  }

  if (include("x86")) {
    tasks.push(
      {
        id: "x86-native-bytes",
        phase: "x86",
        command: "bun",
        args: ["run", "scripts/bench-native-byte-path.ts"],
        timeoutMs: 30 * 60 * 1000,
        env: commonBenchEnv,
      },
      {
        id: "x86-native-pretokenizer",
        phase: "x86",
        command: "bun",
        args: ["run", "scripts/bench-native-pretokenizer.ts", "--mode=baseline"],
        timeoutMs: 20 * 60 * 1000,
        env: commonBenchEnv,
      },
    );
  }

  if (include("competitors")) {
    if (runCompetitorsSweep) {
      tasks.push(
        {
          id: "competitors-bench",
          phase: "competitors",
          command: "bun",
          args: ["run", config.quick ? "scripts/bench-competitors.ts" : "scripts/bench-competitors-stable.ts"],
          timeoutMs: 90 * 60 * 1000,
          env: commonBenchEnv,
        },
        {
          id: "competitors-ram",
          phase: "competitors",
          command: "bun",
          args: ["run", "scripts/bench-ram.ts"],
          timeoutMs: 30 * 60 * 1000,
          env: commonBenchEnv,
        },
      );
    }
  }

  return tasks;
}

function renderMarkdown(state: LoopState): string {
  const latest = state.cycles[state.cycles.length - 1];
  const lines: string[] = [];
  lines.push("# Ralph Loop Report");
  lines.push("");
  lines.push(`- Updated: ${state.updatedAt}`);
  lines.push(`- Loop ID: \`${state.id}\``);
  lines.push(`- Cycles completed: ${state.cycles.length}`);
  lines.push(`- Tasks total: ${state.totals.tasks} (ok=${state.totals.succeededTasks}, failed=${state.totals.failedTasks})`);
  lines.push(`- Config phases: ${state.runConfig.phases.join(", ")}`);
  lines.push(`- Config speed: ${state.runConfig.quick ? "fast" : "full"}`);
  if (!latest) {
    return `${lines.join("\n")}\n`;
  }
  lines.push("");
  lines.push(`## Latest Cycle (${latest.index})`);
  lines.push("");
  lines.push("| Task | Phase | Status | Duration (s) | Exit |");
  lines.push("|---|---|---:|---:|---:|");
  for (const task of latest.tasks) {
    lines.push(
      `| ${task.id} | ${task.phase} | ${task.ok ? "OK" : "FAIL"} | ${(task.durationMs / 1000).toFixed(2)} | ${task.exitCode} |`,
    );
  }
  lines.push("");
  lines.push(`Cycle status: ${latest.ok ? "OK" : "FAIL"}`);
  return `${lines.join("\n")}\n`;
}

function loadOrCreateState(config: CliConfig): LoopState {
  if (!config.fresh && existsSync(config.statePath)) {
    try {
      const parsed = JSON.parse(readFileSync(config.statePath, "utf8")) as LoopState;
      if (parsed && parsed.version === 1 && Array.isArray(parsed.cycles)) {
        parsed.updatedAt = new Date().toISOString();
        return parsed;
      }
    } catch {
      // fall through to new state
    }
  }
  const now = new Date().toISOString();
  return {
    version: 1,
    id: `ralph-loop-${dateTag()}`,
    createdAt: now,
    updatedAt: now,
    startedAt: now,
    runConfig: {
      quick: config.quick,
      phases: [...config.phases],
      maxCycles: config.maxCycles,
      hours: config.hours,
      sleepSeconds: config.sleepSeconds,
      stopOnFailure: config.stopOnFailure,
      scorecardEachCycle: config.scorecardEachCycle,
      fullGovernanceEvery: config.fullGovernanceEvery,
      competitorsEvery: config.competitorsEvery,
    },
    cycles: [],
    totals: {
      tasks: 0,
      failedTasks: 0,
      succeededTasks: 0,
    },
  };
}

function persistState(state: LoopState, config: CliConfig): void {
  state.updatedAt = new Date().toISOString();
  writeJson(config.statePath, state);
  ensureDir(resolvePath("bench", "charts"));
  writeFileSync(config.reportPath, renderMarkdown(state), "utf8");
}

function shouldStop(state: LoopState, config: CliConfig, deadlineMs: number | null): boolean {
  if (config.maxCycles != null && state.cycles.length >= config.maxCycles) {
    return true;
  }
  if (deadlineMs != null && Date.now() >= deadlineMs) {
    return true;
  }
  return false;
}

assertLoopEnabled();
const config = parseCli(process.argv.slice(2));
const lock = acquireBenchmarkLock({ label: "ralph-loop" });

try {
  const state = loadOrCreateState(config);
  persistState(state, config);

  const deadlineMs = config.hours != null ? Date.now() + Math.floor(config.hours * 60 * 60 * 1000) : null;

  section("Ralph loop");
  console.log(`state: ${config.statePath}`);
  console.log(`report: ${config.reportPath}`);
  console.log(`phases: ${config.phases.join(", ")}`);
  console.log(`default phases: ${DEFAULT_PHASES.join(", ")}`);
  console.log(`speed: ${config.quick ? "fast" : "full"}`);
  console.log(`full governance cadence: every ${config.fullGovernanceEvery} cycle(s)`);
  console.log(`competitor sweep cadence: every ${config.competitorsEvery} cycle(s)`);
  console.log(`max cycles: ${config.maxCycles ?? "unbounded"}`);
  console.log(`deadline: ${deadlineMs == null ? "none" : new Date(deadlineMs).toISOString()}`);

  while (!shouldStop(state, config, deadlineMs)) {
    const cycleIndex = state.cycles.length + 1;
    const tasks = buildTasks(config, cycleIndex);
    if (tasks.length === 0) {
      throw new Error(`no tasks selected for Ralph loop cycle ${cycleIndex}`);
    }

    const cycle: CycleRecord = {
      index: cycleIndex,
      startedAt: new Date().toISOString(),
      ok: true,
      tasks: [],
    };
    section(`Ralph cycle ${cycle.index}`);

    for (const task of tasks) {
      if (deadlineMs != null && Date.now() >= deadlineMs) {
        console.log(`deadline reached before task ${task.id}`);
        break;
      }
      section(`Task: ${task.id}`);
      const startedAt = new Date().toISOString();
      const startedMs = Date.now();
      const result = runCommand(task.command, task.args, {
        allowFailure: true,
        timeoutMs: task.timeoutMs,
        env: task.env,
      });
      const endedMs = Date.now();
      const endedAt = new Date().toISOString();
      const ok = result.code === 0;
      const record: TaskRunRecord = {
        id: task.id,
        phase: task.phase,
        command: task.command,
        args: [...task.args],
        startedAt,
        endedAt,
        durationMs: endedMs - startedMs,
        exitCode: result.code,
        ok,
        stdoutTail: shortTail(result.stdout),
        stderrTail: shortTail(result.stderr),
      };
      cycle.tasks.push(record);
      state.totals.tasks += 1;
      if (ok) {
        state.totals.succeededTasks += 1;
      } else {
        state.totals.failedTasks += 1;
        cycle.ok = false;
      }
      const summary = `exit=${record.exitCode} duration=${(record.durationMs / 1000).toFixed(2)}s`;
      console.log(summary);
      if (!ok) {
        if (record.stderrTail.length > 0) {
          console.log(`stderr tail:\n${record.stderrTail}`);
        } else if (record.stdoutTail.length > 0) {
          console.log(`stdout tail:\n${record.stdoutTail}`);
        }
      }
      persistState(state, config);
      if (!ok && config.stopOnFailure) {
        console.log("stop-on-failure enabled; terminating loop.");
        break;
      }
    }

    if (config.scorecardEachCycle) {
      section("Scorecard refresh");
      const scorecard = runCommand("bun", ["run", "scripts/bench-scorecard.ts"], {
        allowFailure: true,
        env: {
          TURBOTOKEN_BENCH_SPEED: config.quick ? "fast" : "full",
          TURBOTOKEN_BENCH_INCLUDE_CUDA: "0",
        },
      });
      if (scorecard.code !== 0) {
        cycle.ok = false;
        state.totals.tasks += 1;
        state.totals.failedTasks += 1;
      } else {
        state.totals.tasks += 1;
        state.totals.succeededTasks += 1;
      }
    }

    cycle.endedAt = new Date().toISOString();
    cycle.durationMs = new Date(cycle.endedAt).getTime() - new Date(cycle.startedAt).getTime();
    state.cycles.push(cycle);
    persistState(state, config);

    const cycleSummary = `cycle=${cycle.index} status=${cycle.ok ? "OK" : "FAIL"} duration=${(
      (cycle.durationMs ?? 0) / 1000
    ).toFixed(2)}s`;
    console.log(cycleSummary);

    if (!cycle.ok && config.stopOnFailure) {
      break;
    }
    if (shouldStop(state, config, deadlineMs)) {
      break;
    }
    if (config.sleepSeconds > 0) {
      console.log(`sleeping ${config.sleepSeconds}s before next cycle`);
      Bun.sleepSync(config.sleepSeconds * 1000);
    }
  }

  section("Ralph loop complete");
  const lastCycle = state.cycles[state.cycles.length - 1];
  console.log(`cycles: ${state.cycles.length}`);
  console.log(`totals: ok=${state.totals.succeededTasks} failed=${state.totals.failedTasks}`);
  if (lastCycle) {
    console.log(`last cycle: ${lastCycle.index} (${lastCycle.ok ? "OK" : "FAIL"})`);
  }

  const artifactPath = resolvePath("bench", "results", `ralph-loop-run-${Date.now()}.json`);
  writeJson(artifactPath, {
    tool: "ralph-loop",
    generatedAt: new Date().toISOString(),
    statePath: config.statePath,
    reportPath: config.reportPath,
    runConfig: state.runConfig,
    cycles: state.cycles.length,
    totals: state.totals,
    lastCycle,
  });
  console.log(`run artifact: ${artifactPath}`);
} finally {
  lock.release();
}
