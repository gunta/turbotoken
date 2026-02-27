import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { expect, test } from "bun:test";
import {
  clearWasmCache,
  encodingForModel,
  getEncoding,
  getEncodingAsync,
  loadWasm,
  trainBpeFromChunkCounts,
  trainBpeFromChunks,
} from "../src/index";

test("fallback encoding roundtrip works before wasm/ranks are loaded", () => {
  const enc = getEncoding("o200k_base");
  const input = "hello";
  expect(enc.decode(enc.encode(input))).toBe(input);
});

test("model helper maps GPT models", () => {
  const enc = encodingForModel("gpt-4o");
  expect(enc.name).toBe("o200k_base");
});

test("wasm utf8 byte path works when wasm artifact exists", async () => {
  const wasmPath = resolve(process.cwd(), "zig-out/bin/turbotoken.wasm");
  if (!existsSync(wasmPath)) {
    return;
  }

  clearWasmCache();
  const bridge = await loadWasm({ wasmPath, forceReload: true });
  const text = "hello wasm";
  const tokens = bridge.encodeUtf8Bytes(text);
  const bytes = bridge.decodeUtf8Bytes(tokens);
  expect(new TextDecoder().decode(bytes)).toBe(text);
});

test("wasm bpe path works with explicit ranks when wasm artifact exists", async () => {
  const wasmPath = resolve(process.cwd(), "zig-out/bin/turbotoken.wasm");
  if (!existsSync(wasmPath)) {
    return;
  }

  const rankPayload = new TextEncoder().encode("YQ== 0\nYg== 1\nYWI= 2\n\n");
  clearWasmCache();
  const enc = await getEncodingAsync("o200k_base", {
    wasm: { wasmPath, forceReload: true },
    rankPayload,
    enableWasmBpe: true,
  });

  const tokens = await enc.encodeAsync("abb");
  expect(tokens).toEqual([2, 1]);
  expect(await enc.countAsync("abb")).toBe(2);
  expect(await enc.decodeAsync(tokens)).toBe("abb");
});

test("wasm training wrappers return expected first merge when wasm artifact exists", async () => {
  const wasmPath = resolve(process.cwd(), "zig-out/bin/turbotoken.wasm");
  if (!existsSync(wasmPath)) {
    return;
  }

  clearWasmCache();
  const fromChunkCounts = await trainBpeFromChunkCounts({
    chunks: "abab",
    chunkOffsets: [0, 2, 4],
    chunkCounts: [1, 1],
    vocabSize: 257,
    minFrequency: 1,
    wasm: { wasmPath, forceReload: true },
  });
  expect(fromChunkCounts.length).toBeGreaterThanOrEqual(1);
  expect(fromChunkCounts[0]).toEqual({ left: 97, right: 98, newId: 256 });

  const fromChunks = await trainBpeFromChunks({
    chunks: ["ab", "ab"],
    vocabSize: 257,
    minFrequency: 1,
    wasm: { wasmPath, forceReload: true },
  });
  expect(fromChunks.length).toBeGreaterThanOrEqual(1);
  expect(fromChunks[0]).toEqual({ left: 97, right: 98, newId: 256 });
});
