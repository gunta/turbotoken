#!/usr/bin/env bun
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { hostname } from "node:os";
import { resolvePath } from "./_lib";

interface LockOwner {
  token?: string;
  pid?: number;
  host?: string;
  acquiredAt?: string;
  acquiredEpochMs?: number;
  label?: string;
  cwd?: string;
  argv?: string[];
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

function processAlive(pid: number): boolean {
  if (!Number.isFinite(pid) || pid <= 0) {
    return false;
  }
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    return code === "EPERM";
  }
}

function lockDirPath(): string {
  const raw = (process.env.TURBOTOKEN_BENCH_LOCK_DIR ?? "").trim();
  if (raw.length > 0) {
    return raw;
  }
  return resolvePath("bench", ".locks", "runtime-local-machine");
}

function ownerPath(lockDir: string): string {
  return resolve(lockDir, "owner.json");
}

function readOwner(lockDir: string): LockOwner | null {
  const path = ownerPath(lockDir);
  if (!existsSync(path)) {
    return null;
  }
  try {
    return JSON.parse(readFileSync(path, "utf8")) as LockOwner;
  } catch {
    return null;
  }
}

function emit(lockDir: string): boolean {
  if (!existsSync(lockDir)) {
    console.log(
      JSON.stringify(
        {
          status: "unlocked",
          lockDir,
          host: hostname(),
          generatedAt: new Date().toISOString(),
        },
        null,
        2,
      ),
    );
    return false;
  }

  const owner = readOwner(lockDir);
  const pid = typeof owner?.pid === "number" ? owner.pid : null;
  const alive = pid != null ? processAlive(pid) : null;
  const acquiredEpochMs = typeof owner?.acquiredEpochMs === "number" ? owner.acquiredEpochMs : null;
  const ageMs = acquiredEpochMs != null ? Date.now() - acquiredEpochMs : null;
  console.log(
    JSON.stringify(
      {
        status: "locked",
        lockDir,
        owner: owner ?? null,
        ownerPidAlive: alive,
        ageMs,
        generatedAt: new Date().toISOString(),
      },
      null,
      2,
    ),
  );
  return true;
}

const args = process.argv.slice(2);
const waitMode = args.includes("--wait");
const timeoutMs = parsePositiveInt(process.env.TURBOTOKEN_BENCH_LOCK_TIMEOUT_MS, 30 * 60 * 1000);
const pollMs = parsePositiveInt(process.env.TURBOTOKEN_BENCH_LOCK_POLL_MS, 1000);
const lockDir = lockDirPath();

if (!waitMode) {
  emit(lockDir);
  process.exit(0);
}

const startedAt = Date.now();
while (true) {
  const locked = emit(lockDir);
  if (!locked) {
    process.exit(0);
  }
  if (Date.now() - startedAt >= timeoutMs) {
    console.error(
      `timed out waiting for benchmark lock to clear after ${Math.round(timeoutMs / 1000)}s: ${lockDir}`,
    );
    process.exit(1);
  }
  Bun.sleepSync(pollMs);
}
