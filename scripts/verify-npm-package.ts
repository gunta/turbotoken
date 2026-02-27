#!/usr/bin/env bun
import { existsSync, statSync } from "node:fs";
import { resolvePath, section, writeJson } from "./_lib";
import { loadWasm } from "../js/src/wasm-loader";

section("Verify npm/WASM package artifacts");

const wasmPath = resolvePath("zig-out", "bin", "turbotoken.wasm");
const resultPath = resolvePath("dist", "npm", `verify-npm-package-${Date.now()}.json`);

if (!existsSync(wasmPath)) {
  writeJson(resultPath, {
    status: "failed",
    reason: `missing wasm artifact at ${wasmPath}`,
  });
  console.error(`Missing WASM artifact: ${wasmPath}`);
  process.exit(1);
}

const wasmBytes = statSync(wasmPath).size;
if (wasmBytes <= 0) {
  writeJson(resultPath, {
    status: "failed",
    reason: `empty wasm artifact at ${wasmPath}`,
    wasmBytes,
  });
  console.error(`Empty WASM artifact: ${wasmPath}`);
  process.exit(1);
}

let encodeHello: number[] = [];
let decodeHello = "";
try {
  const bridge = await loadWasm({ wasmPath, forceReload: true });
  encodeHello = bridge.encodeUtf8Bytes("hello");
  decodeHello = new TextDecoder().decode(bridge.decodeUtf8Bytes(encodeHello));
} catch (error) {
  writeJson(resultPath, {
    status: "failed",
    reason: "failed to instantiate/execute wasm bridge",
    wasmPath,
    wasmBytes,
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
  encodeHello,
  decodeHello,
  note: "npm wrapper remains thin and validates against fresh wasm artifact.",
});

console.log(`WASM/npm package verification passed: ${resultPath}`);
