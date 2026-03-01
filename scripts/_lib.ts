#!/usr/bin/env bun
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir, hostname } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptsDir = dirname(fileURLToPath(import.meta.url));

export const repoRoot = resolve(scriptsDir, "..");

export interface RunOptions {
  cwd?: string;
  env?: Record<string, string>;
  allowFailure?: boolean;
  stdin?: string;
  timeoutMs?: number;
}

export interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

interface BenchLockOwner {
  token: string;
  pid: number;
  host: string;
  acquiredAt: string;
  acquiredEpochMs: number;
  label: string;
  cwd: string;
  argv: string[];
}

export interface BenchLockOptions {
  label: string;
  timeoutMs?: number;
  pollMs?: number;
  staleMs?: number;
  lockDir?: string;
}

export interface BenchLockHandle {
  acquired: boolean;
  inherited: boolean;
  lockDir: string | null;
  release: () => void;
}

const BENCH_LOCK_HELD_ENV = "TURBOTOKEN_BENCH_LOCK_HELD";
const BENCH_LOCK_DIR_ENV = "TURBOTOKEN_BENCH_LOCK_DIR";
const BENCH_LOCK_TOKEN_ENV = "TURBOTOKEN_BENCH_LOCK_TOKEN";
const BENCH_LOCK_DISABLE_ENV = "TURBOTOKEN_BENCH_LOCK_DISABLE";
const BENCH_LOCK_TIMEOUT_ENV = "TURBOTOKEN_BENCH_LOCK_TIMEOUT_MS";
const BENCH_LOCK_POLL_ENV = "TURBOTOKEN_BENCH_LOCK_POLL_MS";
const BENCH_LOCK_STALE_ENV = "TURBOTOKEN_BENCH_LOCK_STALE_MS";

const activeBenchLocks = new Map<string, string>();
let benchLockExitHookInstalled = false;

function lockEnabled(): boolean {
  const raw = (process.env[BENCH_LOCK_DISABLE_ENV] ?? "").trim().toLowerCase();
  if (raw === "1" || raw === "true" || raw === "yes" || raw === "on") {
    return false;
  }
  return true;
}

function parsePositiveInt(raw: string | undefined, fallback: number): number {
  if (!raw) {
    return fallback;
  }
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return parsed;
}

function defaultBenchLockDir(): string {
  const raw = (process.env[BENCH_LOCK_DIR_ENV] ?? "").trim();
  if (raw.length > 0) {
    return raw;
  }
  return resolvePath("bench", ".locks", "runtime-local-machine");
}

function lockOwnerPath(lockDir: string): string {
  return resolve(lockDir, "owner.json");
}

function readLockOwner(lockDir: string): BenchLockOwner | null {
  const path = lockOwnerPath(lockDir);
  if (!existsSync(path)) {
    return null;
  }
  try {
    const payload = JSON.parse(readFileSync(path, "utf8")) as Partial<BenchLockOwner>;
    if (
      typeof payload.token !== "string" ||
      typeof payload.pid !== "number" ||
      typeof payload.host !== "string" ||
      typeof payload.acquiredEpochMs !== "number"
    ) {
      return null;
    }
    return {
      token: payload.token,
      pid: payload.pid,
      host: payload.host,
      acquiredAt: typeof payload.acquiredAt === "string" ? payload.acquiredAt : new Date(payload.acquiredEpochMs).toISOString(),
      acquiredEpochMs: payload.acquiredEpochMs,
      label: typeof payload.label === "string" ? payload.label : "unknown",
      cwd: typeof payload.cwd === "string" ? payload.cwd : "",
      argv: Array.isArray(payload.argv) ? payload.argv.map((item) => String(item)) : [],
    };
  } catch {
    return null;
  }
}

function processAlive(pid: number): boolean {
  if (!Number.isFinite(pid) || pid <= 0) {
    return false;
  }
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === "EPERM") {
      return true;
    }
    return false;
  }
}

function removeLockDir(lockDir: string): void {
  try {
    rmSync(lockDir, { recursive: true, force: true });
  } catch {
    // best-effort lock cleanup
  }
}

function installBenchLockExitHook(): void {
  if (benchLockExitHookInstalled) {
    return;
  }
  benchLockExitHookInstalled = true;
  process.on("exit", () => {
    for (const [lockDir, token] of activeBenchLocks.entries()) {
      const owner = readLockOwner(lockDir);
      if (owner && owner.token !== token) {
        continue;
      }
      removeLockDir(lockDir);
    }
    activeBenchLocks.clear();
  });
}

export function acquireBenchmarkLock(options: BenchLockOptions): BenchLockHandle {
  if (!lockEnabled()) {
    return {
      acquired: false,
      inherited: false,
      lockDir: null,
      release: () => {},
    };
  }

  if ((process.env[BENCH_LOCK_HELD_ENV] ?? "").trim() === "1") {
    return {
      acquired: false,
      inherited: true,
      lockDir: process.env[BENCH_LOCK_DIR_ENV] ?? null,
      release: () => {},
    };
  }

  const lockDir = options.lockDir ?? defaultBenchLockDir();
  const timeoutMs = options.timeoutMs ?? parsePositiveInt(process.env[BENCH_LOCK_TIMEOUT_ENV], 30 * 60 * 1000);
  const pollMs = options.pollMs ?? parsePositiveInt(process.env[BENCH_LOCK_POLL_ENV], 1000);
  const staleMs = options.staleMs ?? parsePositiveInt(process.env[BENCH_LOCK_STALE_ENV], 12 * 60 * 60 * 1000);
  const startedAt = Date.now();
  const selfHost = hostname();
  mkdirSync(dirname(lockDir), { recursive: true });

  while (true) {
    try {
      mkdirSync(lockDir, { recursive: false });
      const token = `${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const owner: BenchLockOwner = {
        token,
        pid: process.pid,
        host: selfHost,
        acquiredAt: new Date().toISOString(),
        acquiredEpochMs: Date.now(),
        label: options.label,
        cwd: process.cwd(),
        argv: [...process.argv],
      };
      writeFileSync(lockOwnerPath(lockDir), `${JSON.stringify(owner, null, 2)}\n`, "utf8");
      activeBenchLocks.set(lockDir, token);
      installBenchLockExitHook();

      const previousHeld = process.env[BENCH_LOCK_HELD_ENV];
      const previousDir = process.env[BENCH_LOCK_DIR_ENV];
      const previousToken = process.env[BENCH_LOCK_TOKEN_ENV];
      process.env[BENCH_LOCK_HELD_ENV] = "1";
      process.env[BENCH_LOCK_DIR_ENV] = lockDir;
      process.env[BENCH_LOCK_TOKEN_ENV] = token;

      let released = false;
      const release = () => {
        if (released) {
          return;
        }
        released = true;
        activeBenchLocks.delete(lockDir);
        const currentOwner = readLockOwner(lockDir);
        if (!currentOwner || currentOwner.token === token) {
          removeLockDir(lockDir);
        }
        if (previousHeld === undefined) {
          delete process.env[BENCH_LOCK_HELD_ENV];
        } else {
          process.env[BENCH_LOCK_HELD_ENV] = previousHeld;
        }
        if (previousDir === undefined) {
          delete process.env[BENCH_LOCK_DIR_ENV];
        } else {
          process.env[BENCH_LOCK_DIR_ENV] = previousDir;
        }
        if (previousToken === undefined) {
          delete process.env[BENCH_LOCK_TOKEN_ENV];
        } else {
          process.env[BENCH_LOCK_TOKEN_ENV] = previousToken;
        }
      };

      return {
        acquired: true,
        inherited: false,
        lockDir,
        release,
      };
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      if (code !== "EEXIST") {
        throw error;
      }
    }

    const now = Date.now();
    const owner = readLockOwner(lockDir);
    let stale = false;
    if (owner) {
      const ownerAgeMs = now - owner.acquiredEpochMs;
      if (owner.host === selfHost && !processAlive(owner.pid)) {
        stale = true;
      } else if (ownerAgeMs >= staleMs && owner.host === selfHost && !processAlive(owner.pid)) {
        stale = true;
      }
    } else {
      try {
        const ageMs = now - statSync(lockDir).mtimeMs;
        if (ageMs >= staleMs) {
          stale = true;
        }
      } catch {
        stale = true;
      }
    }

    if (stale) {
      removeLockDir(lockDir);
      continue;
    }

    if (now - startedAt >= timeoutMs) {
      const ownerSummary = owner
        ? `held by pid=${owner.pid} host=${owner.host} label=${owner.label} acquiredAt=${owner.acquiredAt}`
        : "held by unknown owner";
      throw new Error(
        `timed out waiting for benchmark lock (${Math.round(timeoutMs / 1000)}s): ${lockDir} (${ownerSummary})`,
      );
    }

    Bun.sleepSync(pollMs);
  }
}

export function withBenchmarkLock<T>(label: string, fn: () => T, options: Omit<BenchLockOptions, "label"> = {}): T {
  const lock = acquireBenchmarkLock({
    label,
    ...options,
  });
  try {
    return fn();
  } finally {
    lock.release();
  }
}

export async function withBenchmarkLockAsync<T>(
  label: string,
  fn: () => Promise<T>,
  options: Omit<BenchLockOptions, "label"> = {},
): Promise<T> {
  const lock = acquireBenchmarkLock({
    label,
    ...options,
  });
  try {
    return await fn();
  } finally {
    lock.release();
  }
}

export function resolvePath(...segments: string[]): string {
  return resolve(repoRoot, ...segments);
}

export function pythonExecutable(): string {
  const venvPython = resolvePath(".venv", "bin", "python");
  return existsSync(venvPython) ? venvPython : "python3";
}

export function ensurePythonDevEnvironment(): string {
  const venvPython = resolvePath(".venv", "bin", "python");
  const preferUv = commandExists("uv") && process.env.TURBOTOKEN_PY_INSTALLER !== "pip";

  if (!existsSync(venvPython)) {
    if (preferUv) {
      section("Bootstrap Python virtual environment (.venv) with uv");
      const uvVenv = runCommand("uv", ["venv", "--python", "python3", ".venv"], { allowFailure: true });
      if (uvVenv.code !== 0) {
        throw new Error(`uv failed to bootstrap .venv:\n${uvVenv.stderr || uvVenv.stdout}`);
      }
    } else {
      if (!commandExists("python3")) {
        throw new Error("python3 is required to bootstrap .venv");
      }
      section("Bootstrap Python virtual environment (.venv)");
      runCommand("python3", ["-m", "venv", ".venv"]);
    }
  }

  const pytestCheck = runCommand(venvPython, ["-m", "pytest", "--version"], { allowFailure: true });
  if (pytestCheck.code !== 0) {
    section("Install Python dev dependencies into .venv");
    if (preferUv) {
      const uvInstall = runCommand(
        "uv",
        ["pip", "install", "--python", venvPython, "-e", ".[dev]"],
        { allowFailure: true },
      );
      if (uvInstall.code !== 0) {
        console.warn("uv install failed, falling back to pip");
        runCommand(venvPython, ["-m", "pip", "install", "-U", "pip"]);
        runCommand(venvPython, ["-m", "pip", "install", "-e", ".[dev]"]);
      }
    } else {
      runCommand(venvPython, ["-m", "pip", "install", "-U", "pip"]);
      runCommand(venvPython, ["-m", "pip", "install", "-e", ".[dev]"]);
    }
  }

  return venvPython;
}

export function ensureDir(path: string): void {
  mkdirSync(path, { recursive: true });
}

export function section(title: string): void {
  console.log(`\n== ${title} ==`);
}

export function commandExists(command: string): boolean {
  if (command.includes("/") || command.includes("\\")) {
    return existsSync(command);
  }
  const checker = process.platform === "win32" ? "where" : "which";
  const result = spawnSync(checker, [command], { stdio: "ignore" });
  return result.status === 0;
}

export function zigExecutable(): string {
  const envZig = process.env.ZIG_EXE;
  if (envZig && existsSync(envZig)) {
    return envZig;
  }

  const protoRoot = resolve(homedir(), ".proto", "tools", "zig");
  if (existsSync(protoRoot)) {
    const candidates = readdirSync(protoRoot)
      .map((version) => resolve(protoRoot, version, "zig"))
      .filter((path) => existsSync(path));

    if (candidates.length > 0) {
      candidates.sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
      return candidates[0];
    }
  }

  return "zig";
}

export function runCommand(command: string, args: string[], options: RunOptions = {}): RunResult {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? repoRoot,
    env: { ...process.env, ...options.env },
    input: options.stdin,
    timeout: options.timeoutMs,
    encoding: "utf8",
  });

  let code = result.status ?? 1;
  const stdout = result.stdout ?? "";
  let stderr = result.stderr ?? "";
  if (result.error) {
    if ((result.error as { code?: string }).code === "ETIMEDOUT") {
      code = 124;
    }
    const err = `spawn error: ${result.error.message}`;
    stderr = stderr.trim().length > 0 ? `${stderr.trim()}\n${err}` : err;
  }

  if (code !== 0 && !options.allowFailure) {
    const rendered = [`Command failed (${code}): ${[command, ...args].join(" ")}`];
    if (stdout.trim().length > 0) {
      rendered.push(stdout.trim());
    }
    if (stderr.trim().length > 0) {
      rendered.push(stderr.trim());
    }
    throw new Error(rendered.join("\n\n"));
  }

  return { code, stdout, stderr };
}

export function runShell(command: string, options: RunOptions = {}): RunResult {
  if (process.platform === "win32") {
    return runCommand("cmd.exe", ["/d", "/s", "/c", command], options);
  }
  return runCommand("sh", ["-c", command], options);
}

export function dateTag(d = new Date()): string {
  const yyyy = d.getUTCFullYear();
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(d.getUTCDate()).padStart(2, "0");
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const min = String(d.getUTCMinutes()).padStart(2, "0");
  const ss = String(d.getUTCSeconds()).padStart(2, "0");
  return `${yyyy}${mm}${dd}-${hh}${min}${ss}`;
}

export function writeJson(path: string, value: unknown): void {
  ensureDir(dirname(path));
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}
