#!/usr/bin/env bun
import { existsSync, statSync } from "node:fs";
import { resolvePath, section, writeJson } from "./_lib";
import { loadWasm } from "../js/src/wasm-loader";

section("Verify npm/WASM package artifacts");

const wasmPath = resolvePath("zig-out", "bin", "turbotoken.wasm");
const npmWasmPath = resolvePath("zig-out", "bin", "turbotoken-npm.wasm");
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
try {
  // Verify package default auto-load path (no explicit wasmPath).
  const bridge = await loadWasm({ forceReload: true });
  encodeHello = bridge.encodeUtf8Bytes("hello");
  decodeHello = new TextDecoder().decode(bridge.decodeUtf8Bytes(encodeHello));
} catch (error) {
  writeJson(resultPath, {
    status: "failed",
    reason: "failed to instantiate/execute wasm bridge",
    wasmPath,
    wasmBytes,
    npmWasmPath,
    npmWasmBytes,
    npmWasmLimitBytes,
    error: String(error),
  });
  console.error(`WASM bridge verification failed: ${String(error)}`);
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

writeJson(resultPath, {
  status: "ok",
  wasmPath,
  wasmBytes,
  npmWasmPath,
  npmWasmBytes,
  npmWasmLimitBytes,
  encodeHello,
  decodeHello,
  note: "npm wrapper remains thin, auto-loads local npm wasm by default, and validates roundtrip.",
});

console.log(`WASM/npm package verification passed: ${resultPath}`);
