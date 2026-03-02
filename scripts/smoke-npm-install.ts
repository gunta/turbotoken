#!/usr/bin/env bun
import { existsSync, mkdirSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { commandExists, resolvePath, runCommand, section, writeJson } from "./_lib";

section("npm package smoke install");
const outputPath = resolvePath("dist", "npm", `smoke-npm-install-${Date.now()}.json`);

if (!commandExists("npm")) {
  writeJson(outputPath, {
    status: "failed",
    reason: "npm not found",
  });
  console.error("npm is required for npm package smoke install.");
  process.exit(1);
}

if (!commandExists("bun")) {
  writeJson(outputPath, {
    status: "failed",
    reason: "bun not found",
  });
  console.error("bun is required for npm package smoke install.");
  process.exit(1);
}

const pack = runCommand("npm", ["pack", "--silent"], { allowFailure: true });
if (pack.code !== 0) {
  writeJson(outputPath, {
    status: "failed",
    reason: "npm pack failed",
    stdout: pack.stdout,
    stderr: pack.stderr,
  });
  console.error(pack.stderr.trim() || pack.stdout.trim() || "npm pack failed");
  process.exit(pack.code);
}

const tarballName = pack.stdout
  .trim()
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => line.length > 0)
  .at(-1);

if (!tarballName) {
  writeJson(outputPath, {
    status: "failed",
    reason: "npm pack did not output a tarball filename",
    stdout: pack.stdout,
  });
  console.error("npm pack did not output a tarball filename.");
  process.exit(1);
}

const tarballPath = resolvePath(tarballName);
if (!existsSync(tarballPath)) {
  writeJson(outputPath, {
    status: "failed",
    reason: `packed tarball missing: ${tarballPath}`,
  });
  console.error(`Packed tarball missing: ${tarballPath}`);
  process.exit(1);
}

const tempRoot = mkdtempSync(join(tmpdir(), "turbotoken-npm-smoke-"));
const installDir = join(tempRoot, "install");
const pkgRoot = join(installDir, "node_modules", "turbotoken");
const wasmPath = join(pkgRoot, "zig-out", "bin", "turbotoken.wasm");
const npmWasmPath = join(pkgRoot, "zig-out", "bin", "turbotoken-npm.wasm");

let checkStdout = "";
let checkStderr = "";
let checkCode = 1;

try {
  mkdirSync(installDir, { recursive: true });
  runCommand("npm", ["init", "-y"], { cwd: installDir });
  runCommand("npm", ["install", "--no-audit", "--no-fund", tarballPath], { cwd: installDir });

  if (!existsSync(wasmPath) || statSync(wasmPath).size <= 0) {
    checkCode = 2;
    checkStderr = `missing or empty wasm artifact after npm install: ${wasmPath}`;
  } else if (!existsSync(npmWasmPath) || statSync(npmWasmPath).size <= 0) {
    checkCode = 2;
    checkStderr = `missing or empty npm wasm artifact after npm install: ${npmWasmPath}`;
  } else {
    const checkScript = [
      "import { getEncodingAsync, loadWasm } from 'turbotoken';",
      "const bridge = await loadWasm({ forceReload: true });",
      "const encoded = bridge.encodeUtf8Bytes('hello');",
      "const decoded = new TextDecoder().decode(bridge.decodeUtf8Bytes(encoded));",
      "if (decoded !== 'hello') {",
      "  throw new Error(`roundtrip mismatch: ${decoded}`);",
      "}",
      "const enc = await getEncodingAsync('o200k_base');",
      "const tokens = await enc.encodeAsync('hello from npm package');",
      "const text = await enc.decodeAsync(tokens);",
      "if (text !== 'hello from npm package') {",
      "  throw new Error(`encoding roundtrip mismatch: ${text}`);",
      "}",
      "console.log(JSON.stringify({ encoded, decoded, tokenCount: tokens.length }));",
    ].join("\n");
    const check = runCommand("bun", ["-e", checkScript], {
      cwd: installDir,
      allowFailure: true,
    });
    checkCode = check.code;
    checkStdout = check.stdout.trim();
    checkStderr = check.stderr.trim();
  }
} finally {
  rmSync(tempRoot, { force: true, recursive: true });
  rmSync(tarballPath, { force: true });
}

writeJson(outputPath, {
  status: checkCode === 0 ? "ok" : "failed",
  tarballName,
  checkCode,
  checkStdout,
  checkStderr,
  note: "Packs npm tarball, installs into a temp project, imports package root, and validates default WASM auto-load + encoding roundtrip.",
});

if (checkCode !== 0) {
  console.error(`npm package smoke install failed: ${outputPath}`);
  process.exit(checkCode);
}

console.log(`npm package smoke install passed: ${outputPath}`);
