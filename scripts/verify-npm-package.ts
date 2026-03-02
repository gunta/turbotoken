#!/usr/bin/env bun
import { existsSync, statSync } from "node:fs";
import { resolvePath, section, writeJson } from "./_lib";
import { loadWasm } from "../wrappers/js/src/wasm-loader";
import { loadNative } from "../wrappers/js/src/native-loader";

section("Verify npm/WASM package artifacts");

const wasmPath = resolvePath("zig-out", "bin", "turbotoken.wasm");
const npmWasmPath = resolvePath("zig-out", "bin", "turbotoken-npm.wasm");
const nativeLibExt = process.platform === "darwin" ? "dylib" : process.platform === "linux" ? "so" : process.platform === "win32" ? "dll" : null;
const nativeLibName = nativeLibExt === "dll" ? "turbotoken.dll" : nativeLibExt ? `libturbotoken.${nativeLibExt}` : null;
const nativeLibPath = nativeLibName
  ? [
    resolvePath("zig-out", "lib", nativeLibName),
    resolvePath("zig-out", "bin", nativeLibName),
    nativeLibExt === "dll" ? resolvePath("zig-out", "bin", "libturbotoken.dll") : null,
  ].filter((candidate): candidate is string => candidate != null).find((candidate) => existsSync(candidate)) ?? null
  : null;
const resultPath = resolvePath("dist", "npm", `verify-npm-package-${Date.now()}.json`);
const npmWasmLimitBytes = (() => {
  const raw = process.env.TURBOTOKEN_NPM_WASM_MAX_BYTES?.trim();
  if (!raw) {
    return 150 * 1024;
  }
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return 150 * 1024;
  }
  return parsed;
})();

if (!existsSync(wasmPath)) {
  writeJson(resultPath, {
    status: "failed",
    reason: `missing wasm artifact at ${wasmPath}`,
  });
  console.error(`Missing WASM artifact: ${wasmPath}`);
  process.exit(1);
}

if (!existsSync(npmWasmPath)) {
  writeJson(resultPath, {
    status: "failed",
    reason: `missing npm wasm artifact at ${npmWasmPath}`,
  });
  console.error(`Missing npm WASM artifact: ${npmWasmPath}`);
  process.exit(1);
}

const wasmBytes = statSync(wasmPath).size;
const npmWasmBytes = statSync(npmWasmPath).size;
const nativeLibBytes = nativeLibPath ? statSync(nativeLibPath).size : null;
if (wasmBytes <= 0) {
  writeJson(resultPath, {
    status: "failed",
    reason: `empty wasm artifact at ${wasmPath}`,
    wasmBytes,
  });
  console.error(`Empty WASM artifact: ${wasmPath}`);
  process.exit(1);
}
if (npmWasmBytes <= 0) {
  writeJson(resultPath, {
    status: "failed",
    reason: `empty npm wasm artifact at ${npmWasmPath}`,
    wasmBytes,
    npmWasmBytes,
  });
  console.error(`Empty npm WASM artifact: ${npmWasmPath}`);
  process.exit(1);
}
if (nativeLibBytes != null && nativeLibBytes <= 0) {
  writeJson(resultPath, {
    status: "failed",
    reason: `empty host native library at ${nativeLibPath}`,
    wasmBytes,
    npmWasmBytes,
    nativeLibBytes,
  });
  console.error(`Empty host native library: ${nativeLibPath}`);
  process.exit(1);
}
if (npmWasmBytes > npmWasmLimitBytes) {
  writeJson(resultPath, {
    status: "failed",
    reason: `npm wasm artifact exceeds size limit (${npmWasmBytes} > ${npmWasmLimitBytes})`,
    wasmPath,
    wasmBytes,
    npmWasmPath,
    npmWasmBytes,
    npmWasmLimitBytes,
  });
  console.error(`npm wasm artifact exceeds size limit: ${npmWasmBytes} > ${npmWasmLimitBytes}`);
  process.exit(1);
}

let encodeHello: number[] = [];
let decodeHello = "";
let nativeEncodeHello: number[] = [];
let nativeDecodeHello = "";
let nativeCheckStatus: "ok" | "skipped" | "failed" = "skipped";
try {
  // Verify package default auto-load path (no explicit wasmPath).
  const bridge = await loadWasm({ forceReload: true });
  encodeHello = bridge.encodeUtf8Bytes("hello");
  decodeHello = new TextDecoder().decode(bridge.decodeUtf8Bytes(encodeHello));
  if (nativeLibPath) {
    const nativeBridge = await loadNative({ nativeLibPath, forceReload: true });
    nativeEncodeHello = nativeBridge.encodeUtf8Bytes("hello");
    nativeDecodeHello = new TextDecoder().decode(nativeBridge.decodeUtf8Bytes(nativeEncodeHello));
    nativeCheckStatus = "ok";
  }
} catch (error) {
  writeJson(resultPath, {
    status: "failed",
    reason: "failed to instantiate/execute wasm/native bridge",
    wasmPath,
    wasmBytes,
    npmWasmPath,
    npmWasmBytes,
    nativeLibPath,
    nativeLibBytes,
    npmWasmLimitBytes,
    error: String(error),
  });
  console.error(`WASM/native bridge verification failed: ${String(error)}`);
  process.exit(1);
}

if (decodeHello !== "hello") {
  writeJson(resultPath, {
    status: "failed",
    reason: "roundtrip mismatch",
    wasmPath,
    wasmBytes,
    encodeHello,
    decodeHello,
  });
  console.error(`WASM roundtrip mismatch: got ${JSON.stringify(decodeHello)}`);
  process.exit(1);
}
if (nativeCheckStatus === "ok" && nativeDecodeHello !== "hello") {
  writeJson(resultPath, {
    status: "failed",
    reason: "native roundtrip mismatch",
    nativeLibPath,
    nativeLibBytes,
    nativeEncodeHello,
    nativeDecodeHello,
  });
  console.error(`Native roundtrip mismatch: got ${JSON.stringify(nativeDecodeHello)}`);
  process.exit(1);
}

writeJson(resultPath, {
  status: "ok",
  wasmPath,
  wasmBytes,
  npmWasmPath,
  npmWasmBytes,
  nativeLibPath,
  nativeLibBytes,
  nativeCheckStatus,
  npmWasmLimitBytes,
  encodeHello,
  decodeHello,
  nativeEncodeHello,
  nativeDecodeHello,
  note: "npm wrapper remains thin, validates host native bridge, and auto-loads npm wasm by default with fallback.",
});

console.log(`WASM/npm package verification passed: ${resultPath}`);
