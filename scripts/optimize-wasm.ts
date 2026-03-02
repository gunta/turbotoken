#!/usr/bin/env bun
import { existsSync, mkdirSync, renameSync, rmSync, statSync } from "node:fs";
import { basename } from "node:path";
import { commandExists, resolvePath, runCommand, section, writeJson } from "./_lib";

interface OptimizeResult {
  inputPath: string;
  outputPath: string;
  beforeBytes: number;
  afterBytes: number;
  replacedInPlace: boolean;
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

function defaultBinaryenVersion(): string {
  const raw = process.env.TURBOTOKEN_BINARYEN_VERSION?.trim();
  if (raw && raw.length > 0) {
    return raw;
  }
  return "version_126";
}

function binaryenArchiveUrl(version: string): string {
  const file = `binaryen-${version}-arm64-macos.tar.gz`;
  return `https://github.com/WebAssembly/binaryen/releases/download/${version}/${file}`;
}

function ensureWasmOptBinary(): string {
  const override = process.env.TURBOTOKEN_WASM_OPT_BIN?.trim();
  if (override && existsSync(override)) {
    return override;
  }
  if (commandExists("wasm-opt")) {
    return "wasm-opt";
  }

  const version = defaultBinaryenVersion();
  const toolchainRoot = resolvePath(".cache", "turbotoken", "toolchains");
  const binaryenDir = resolvePath(".cache", "turbotoken", "toolchains", "binaryen");
  const wasmOptPath = resolvePath(".cache", "turbotoken", "toolchains", "binaryen", "bin", "wasm-opt");
  if (existsSync(wasmOptPath)) {
    return wasmOptPath;
  }

  if (!commandExists("curl")) {
    throw new Error("curl is required to download binaryen (wasm-opt)");
  }
  if (!commandExists("tar")) {
    throw new Error("tar is required to extract binaryen (wasm-opt)");
  }

  mkdirSync(toolchainRoot, { recursive: true });
  const archivePath = resolvePath(".cache", "turbotoken", "toolchains", `binaryen-${version}.tar.gz`);
  const unpackedDir = resolvePath(".cache", "turbotoken", "toolchains", `binaryen-${version}`);
  const unpackedLegacyDir = resolvePath(".cache", "turbotoken", "toolchains", `binaryen-${version.replace("version_", "version_")}`);

  runCommand("curl", ["-L", "--fail", "-o", archivePath, binaryenArchiveUrl(version)]);
  runCommand("tar", ["-xzf", archivePath, "-C", toolchainRoot]);
  rmSync(archivePath, { force: true });

  const extractedName = basename(binaryenArchiveUrl(version), ".tar.gz");
  const extractedDir = resolvePath(".cache", "turbotoken", "toolchains", extractedName);
  const candidateDir = existsSync(extractedDir)
    ? extractedDir
    : existsSync(unpackedDir)
      ? unpackedDir
      : unpackedLegacyDir;
  if (!existsSync(candidateDir)) {
    throw new Error(`binaryen extraction failed; expected directory not found for ${version}`);
  }

  rmSync(binaryenDir, { recursive: true, force: true });
  renameSync(candidateDir, binaryenDir);
  if (!existsSync(wasmOptPath)) {
    throw new Error(`wasm-opt not found after binaryen install (${wasmOptPath})`);
  }
  return wasmOptPath;
}

function optimizeOne(
  wasmOptBin: string,
  inputPath: string,
  options: { replaceInPlace: boolean },
): OptimizeResult {
  if (!existsSync(inputPath)) {
    throw new Error(`missing input wasm: ${inputPath}`);
  }
  const beforeBytes = statSync(inputPath).size;
  if (beforeBytes <= 0) {
    throw new Error(`input wasm is empty: ${inputPath}`);
  }

  const outputPath = options.replaceInPlace
    ? `${inputPath}.opt`
    : inputPath.replace(/\.wasm$/i, ".opt.wasm");
  runCommand(wasmOptBin, [
    "-Oz",
    "--enable-bulk-memory",
    "--strip-debug",
    "--strip-producers",
    inputPath,
    "-o",
    outputPath,
  ]);

  const optimizedBytes = statSync(outputPath).size;
  if (optimizedBytes <= 0) {
    throw new Error(`optimized wasm is empty: ${outputPath}`);
  }

  let finalOutputPath = outputPath;
  if (options.replaceInPlace) {
    renameSync(outputPath, inputPath);
    finalOutputPath = inputPath;
  }
  const afterBytes = statSync(finalOutputPath).size;

  return {
    inputPath,
    outputPath: finalOutputPath,
    beforeBytes,
    afterBytes,
    replacedInPlace: options.replaceInPlace,
  };
}

section("Optimize WASM binaries (wasm-opt)");

const outputPath = resolvePath("dist", "npm", `optimize-wasm-${Date.now()}.json`);
const npmWasmPath = resolvePath("zig-out", "bin", "turbotoken-npm.wasm");
const fullWasmPath = resolvePath("zig-out", "bin", "turbotoken.wasm");
const optimizeFull = ["1", "true", "yes", "on"].includes(
  (process.env.TURBOTOKEN_WASM_OPTIMIZE_FULL ?? "").trim().toLowerCase(),
);
const sizeLimitBytes = parsePositiveInt(process.env.TURBOTOKEN_NPM_WASM_MAX_BYTES, 150 * 1024);

let wasmOptBin = "";
const results: OptimizeResult[] = [];
let status: "ok" | "failed" = "ok";
let reason: string | null = null;
try {
  wasmOptBin = ensureWasmOptBinary();
  results.push(optimizeOne(wasmOptBin, npmWasmPath, { replaceInPlace: true }));
  if (optimizeFull && existsSync(fullWasmPath)) {
    results.push(optimizeOne(wasmOptBin, fullWasmPath, { replaceInPlace: true }));
  }
} catch (error) {
  status = "failed";
  reason = String(error);
}

const npmResult = results.find((row) => row.outputPath === npmWasmPath || row.inputPath === npmWasmPath) ?? null;
const npmWasmBytes = existsSync(npmWasmPath) ? statSync(npmWasmPath).size : null;
const npmWithinLimit = npmWasmBytes != null ? npmWasmBytes <= sizeLimitBytes : false;
if (status === "ok" && !npmWithinLimit) {
  status = "failed";
  reason = `optimized npm wasm exceeds size limit (${npmWasmBytes} > ${sizeLimitBytes})`;
}

writeJson(outputPath, {
  status,
  reason,
  wasmOptBin: wasmOptBin || null,
  sizeLimitBytes,
  npmWasmPath,
  npmWasmBytes,
  npmWithinLimit,
  optimizeFull,
  results,
  note: "Runs wasm-opt -Oz on npm wasm (and optional full wasm) with bulk-memory enabled.",
});

if (status !== "ok") {
  console.error(`WASM optimization failed: ${outputPath}`);
  process.exit(1);
}

if (!npmResult) {
  console.warn(`WASM optimization completed with no npm optimization row: ${outputPath}`);
} else {
  console.log(
    `Optimized npm wasm: ${npmResult.beforeBytes} -> ${npmResult.afterBytes} bytes ` +
      `(${npmWasmPath}, limit=${sizeLimitBytes})`,
  );
}
console.log(`Wrote wasm optimization report: ${outputPath}`);
