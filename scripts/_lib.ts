#!/usr/bin/env bun
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptsDir = dirname(fileURLToPath(import.meta.url));

export const repoRoot = resolve(scriptsDir, "..");

export interface RunOptions {
  cwd?: string;
  env?: Record<string, string>;
  allowFailure?: boolean;
  stdin?: string;
}

export interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

export function resolvePath(...segments: string[]): string {
  return resolve(repoRoot, ...segments);
}

export function pythonExecutable(): string {
  const venvPython = resolvePath(".venv", "bin", "python");
  return existsSync(venvPython) ? venvPython : "python3";
}

export function ensureDir(path: string): void {
  mkdirSync(path, { recursive: true });
}

export function section(title: string): void {
  console.log(`\n== ${title} ==`);
}

export function commandExists(command: string): boolean {
  const checker = process.platform === "win32" ? "where" : "which";
  const result = spawnSync(checker, [command], { stdio: "ignore" });
  return result.status === 0;
}

export function runCommand(command: string, args: string[], options: RunOptions = {}): RunResult {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? repoRoot,
    env: { ...process.env, ...options.env },
    input: options.stdin,
    encoding: "utf8",
  });

  const code = result.status ?? 1;
  const stdout = result.stdout ?? "";
  const stderr = result.stderr ?? "";

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
