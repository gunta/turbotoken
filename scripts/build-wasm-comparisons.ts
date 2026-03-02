#!/usr/bin/env bun
import { existsSync, mkdirSync, readFileSync, statSync } from "node:fs";
import { gzipSync } from "node:zlib";
import {
  acquireBenchmarkLock,
  commandExists,
  resolvePath,
  runCommand,
  section,
  writeJson,
  zigExecutable,
} from "./_lib";

interface SizeRow {
  name: string;
  path: string | null;
  bytes: number | null;
  gzipBytes: number | null;
  status: "ok" | "not-built" | "failed";
  detail?: string;
}

function sizeOf(path: string): { bytes: number; gzipBytes: number } | null {
  if (!existsSync(path)) {
    return null;
  }
  const raw = readFileSync(path);
  return {
    bytes: raw.byteLength,
    gzipBytes: gzipSync(raw, { level: 9 }).byteLength,
  };
}

function locateMoonBin(): string | null {
  const override = process.env.MOON_BIN?.trim();
  if (override && existsSync(override)) {
    return override;
  }
  const home = process.env.HOME?.trim();
  if (home) {
    const defaultMoon = `${home}/.moon/bin/moon`;
    if (existsSync(defaultMoon)) {
      return defaultMoon;
    }
  }
  if (commandExists("moon")) {
    return "moon";
  }
  return null;
}

function runEmscriptenBuild(sourcePath: string, outPath: string): { ok: boolean; detail?: string } {
  const emsdkEnv = resolvePath(".cache", "turbotoken", "toolchains", "emsdk", "emsdk_env.sh");
  const command = [
    `source ${JSON.stringify(emsdkEnv)} >/dev/null`,
    "emcc",
    JSON.stringify(sourcePath),
    "-Oz",
    "-s",
    "WASM=1",
    "-s",
    "STANDALONE_WASM=1",
    "-s",
    "ALLOW_MEMORY_GROWTH=1",
    "-s",
    "EXPORTED_FUNCTIONS=['_malloc','_free','_tt_encode_utf8_bytes','_tt_decode_utf8_bytes']",
    "-s",
    "EXPORTED_RUNTIME_METHODS=[]",
    "-Wl,--no-entry",
    "-o",
    JSON.stringify(outPath),
  ].join(" ");

  const result = runCommand("bash", ["-lc", command], { allowFailure: true });
  if (result.code !== 0) {
    return { ok: false, detail: result.stderr.trim() || result.stdout.trim() || "emcc build failed" };
  }
  return { ok: true };
}

acquireBenchmarkLock({ label: "build-wasm-comparisons" });
section("WASM comparison builds (Zig vs MoonBit vs Emscripten)");

const outputPath = resolvePath("bench", "results", `bench-wasm-comparisons-${Date.now()}.json`);
const rows: SizeRow[] = [];
const errors: string[] = [];

try {
  const zig = zigExecutable();
  if (!commandExists(zig)) {
    throw new Error(`zig executable not found: ${zig}`);
  }
  runCommand(zig, ["build", "wasm", "-Doptimize=ReleaseSmall"]);
  runCommand("bun", ["run", "build:wasm:opt"]);

  const zigFullPath = resolvePath("zig-out", "bin", "turbotoken.wasm");
  const zigNpmPath = resolvePath("zig-out", "bin", "turbotoken-npm.wasm");
  const zigFullSize = sizeOf(zigFullPath);
  const zigNpmSize = sizeOf(zigNpmPath);
  rows.push({
    name: "zig-wasm-full",
    path: zigFullPath,
    bytes: zigFullSize?.bytes ?? null,
    gzipBytes: zigFullSize?.gzipBytes ?? null,
    status: zigFullSize ? "ok" : "failed",
    detail: zigFullSize ? undefined : "missing zig full wasm artifact",
  });
  rows.push({
    name: "zig-wasm-npm",
    path: zigNpmPath,
    bytes: zigNpmSize?.bytes ?? null,
    gzipBytes: zigNpmSize?.gzipBytes ?? null,
    status: zigNpmSize ? "ok" : "failed",
    detail: zigNpmSize ? undefined : "missing zig npm wasm artifact",
  });
} catch (error) {
  errors.push(String(error));
}

const moonBin = locateMoonBin();
const moonManifest = resolvePath("bench", "wasm", "moonbit", "moon.mod.json");
if (moonBin === null) {
  rows.push({
    name: "moonbit-wasm-gc",
    path: null,
    bytes: null,
    gzipBytes: null,
    status: "not-built",
    detail: "moon binary not found",
  });
} else {
  const moonBuild = runCommand(
    moonBin,
    ["build", "--release", "--target", "wasm-gc", "--manifest-path", moonManifest],
    { allowFailure: true },
  );
  if (moonBuild.code !== 0) {
    rows.push({
      name: "moonbit-wasm-gc",
      path: null,
      bytes: null,
      gzipBytes: null,
      status: "failed",
      detail: moonBuild.stderr.trim() || moonBuild.stdout.trim() || "moon build failed",
    });
  } else {
    const moonReleasePath = resolvePath("bench", "wasm", "moonbit", "_build", "wasm-gc", "release", "build", "cmd", "main", "main.wasm");
    const moonDebugPath = resolvePath("bench", "wasm", "moonbit", "_build", "wasm-gc", "debug", "build", "cmd", "main", "main.wasm");
    const moonPath = existsSync(moonReleasePath) ? moonReleasePath : moonDebugPath;
    const moonSize = sizeOf(moonPath);
    rows.push({
      name: "moonbit-wasm-gc",
      path: moonSize ? moonPath : null,
      bytes: moonSize?.bytes ?? null,
      gzipBytes: moonSize?.gzipBytes ?? null,
      status: moonSize ? "ok" : "failed",
      detail: moonSize ? undefined : "moon build completed but wasm artifact not found",
    });
  }
}

const emSourcePath = resolvePath("bench", "wasm", "emscripten", "utf8_tokenizer.c");
const emOutPath = resolvePath("bench", "wasm", "emscripten", "utf8_tokenizer.wasm");
mkdirSync(resolvePath("bench", "wasm", "emscripten"), { recursive: true });
const emBuild = runEmscriptenBuild(emSourcePath, emOutPath);
if (!emBuild.ok) {
  rows.push({
    name: "emscripten-wasm",
    path: null,
    bytes: null,
    gzipBytes: null,
    status: "failed",
    detail: emBuild.detail ?? "emcc build failed",
  });
} else {
  const emSize = sizeOf(emOutPath);
  rows.push({
    name: "emscripten-wasm",
    path: emSize ? emOutPath : null,
    bytes: emSize?.bytes ?? null,
    gzipBytes: emSize?.gzipBytes ?? null,
    status: emSize ? "ok" : "failed",
    detail: emSize ? undefined : "emcc build completed but wasm artifact not found",
  });
}

writeJson(outputPath, {
  generatedAt: new Date().toISOString(),
  status: errors.length === 0 ? "ok" : "failed",
  errors,
  rows,
  note: "Builds comparison WASM artifacts (MoonBit WASM-GC and Emscripten) and reports raw/gzip sizes alongside Zig outputs.",
});

if (errors.length > 0) {
  console.error(`WASM comparison build failed: ${outputPath}`);
  process.exit(1);
}

for (const row of rows) {
  const sizeText = row.bytes == null ? "-" : `${row.bytes} bytes`;
  const gzipText = row.gzipBytes == null ? "-" : `${row.gzipBytes} bytes gz`;
  console.log(`${row.name}: ${row.status} (${sizeText}, ${gzipText})`);
}
console.log(`Wrote WASM comparison report: ${outputPath}`);
