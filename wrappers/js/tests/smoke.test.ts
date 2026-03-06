import { existsSync } from "node:fs";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { join } from "node:path";
import { expect, test } from "bun:test";
import {
  clearNativeCache,
  clearWasmCache,
  encodingForModel,
  getEncoding,
  getEncodingAsync,
  loadNative,
  loadWasm,
  trainBpeFromChunkCounts,
  trainBpeFromChunks,
} from "../src/index";

test("fallback encoding roundtrip works before wasm/ranks are loaded", () => {
  const enc = getEncoding("o200k_base");
  const input = "hello";
  expect(enc.decode(enc.encode(input))).toBe(input);
});

test("fallback token-limit and generator helpers work before wasm is loaded", () => {
  const enc = getEncoding("o200k_base");
  const input = "hello";
  const count = enc.countTokens(input);
  expect(count).toBe(enc.count(input));
  expect(enc.isWithinTokenLimit(input, count)).toBe(count);
  expect(enc.isWithinTokenLimit(input, count - 1)).toBe(false);

  const encodedChunks = [...enc.encodeGenerator(input)];
  expect(encodedChunks.length).toBe(1);
  const tokens = encodedChunks[0];
  expect(tokens).toEqual(enc.encode(input));
  expect([...enc.decodeGenerator(tokens)]).toEqual([input]);
});

test("fallback chat helpers are internally consistent", () => {
  const enc = getEncoding("o200k_base");
  const chat = [
    { role: "system", content: "You are concise." },
    { role: "user", content: "Hello tokenizer" },
    { role: "assistant", content: "Hi." },
  ];

  const tokens = enc.encodeChat(chat);
  const count = enc.countChat(chat);
  expect(count).toBe(tokens.length);
  expect(enc.countChatTokens(chat)).toBe(count);
  expect(enc.isChatWithinTokenLimit(chat, count)).toBe(count);
  expect(enc.isChatWithinTokenLimit(chat, count - 1)).toBe(false);

  const chunks = [...enc.encodeChatGenerator(chat)];
  const flattened = chunks.flat();
  expect(flattened).toEqual(tokens);
});

test("chat template modes and custom templates are supported", () => {
  const enc = getEncoding("o200k_base");
  const chat = [{ role: "user", content: "hello" }];

  const nativeTokens = enc.encodeChat(chat, { template: "turbotoken_v1" });
  const compatTokens = enc.encodeChat(chat, { template: "im_tokens" });
  expect(nativeTokens).not.toEqual(compatTokens);

  const customTokens = enc.encodeChat(chat, {
    template: {
      messagePrefix: "<msg role='{role}'>",
      messageSuffix: "</msg>",
      assistantPrefix: "<msg role='{role}'>",
    },
  });
  expect(customTokens.length).toBeGreaterThan(0);
});

test("file-path helpers are consistent with text helpers", async () => {
  const enc = getEncoding("o200k_base");
  const dir = mkdtempSync(join(tmpdir(), "turbotoken-js-"));
  const filePath = join(dir, "sample.txt");
  writeFileSync(filePath, "hello from file helper", "utf8");

  const tokens = await enc.encodeFilePath(filePath);
  const count = await enc.countFilePath(filePath);
  expect(count).toBe(tokens.length);
  expect(await enc.isFilePathWithinTokenLimit(filePath, count)).toBe(count);
  expect(await enc.isFilePathWithinTokenLimit(filePath, count - 1)).toBe(false);
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

test("native utf8 byte path works when host shared library exists", async () => {
  const ext = process.platform === "darwin" ? "dylib" : process.platform === "linux" ? "so" : process.platform === "win32" ? "dll" : null;
  if (!ext) {
    return;
  }
  const nativeName = ext === "dll" ? "turbotoken.dll" : `libturbotoken.${ext}`;
  const nativePath = resolve(process.cwd(), `zig-out/lib/${nativeName}`);
  if (!existsSync(nativePath)) {
    return;
  }

  clearNativeCache();
  const bridge = await loadNative({ nativeLibPath: nativePath, forceReload: true });
  const text = "hello native";
  const tokens = bridge.encodeUtf8Bytes(text);
  const bytes = bridge.decodeUtf8Bytes(tokens);
  expect(new TextDecoder().decode(bytes)).toBe(text);
});

test("encoding auto backend prefers native when available", async () => {
  const ext = process.platform === "darwin" ? "dylib" : process.platform === "linux" ? "so" : process.platform === "win32" ? "dll" : null;
  if (!ext) {
    return;
  }
  const nativeName = ext === "dll" ? "turbotoken.dll" : `libturbotoken.${ext}`;
  const nativePath = resolve(process.cwd(), `zig-out/lib/${nativeName}`);
  if (!existsSync(nativePath)) {
    return;
  }

  const enc = await getEncodingAsync("o200k_base", { enableWasmBpe: false });
  expect(enc.backendKind()).toBe("native");
});

test("bpe-enabled sync methods fail loudly before the backend is ready", () => {
  const rankPayload = new TextEncoder().encode("YQ== 0\nYg== 1\nYWI= 2\n\n");
  const enc = getEncoding("o200k_base", {
    backend: "wasm",
    rankPayload,
    enableWasmBpe: true,
  });

  expect(() => enc.encode("abb")).toThrow(/loaded BPE backend/);
  expect(() => enc.count("abb")).toThrow(/loaded BPE backend/);
  expect(() => enc.decode([2, 1])).toThrow(/loaded BPE backend/);
});

test("async encoding defaults to BPE mode with rank payloads", async () => {
  const fullWasmPath = resolve(process.cwd(), "zig-out/bin/turbotoken.wasm");
  if (!existsSync(fullWasmPath)) {
    return;
  }

  const rankPayload = new TextEncoder().encode("YQ== 0\nYg== 1\nYWI= 2\n\n");
  clearWasmCache();
  const enc = await getEncodingAsync("o200k_base", {
    backend: "wasm",
    rankPayload,
  });

  expect(enc.backendKind()).toBe("wasm");
  expect(enc.encode("abb")).toEqual([2, 1]);
  expect(enc.count("abb")).toBe(2);
  expect(enc.decode([2, 1])).toBe("abb");
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
  });

  const tokens = await enc.encodeAsync("abb");
  expect(tokens).toEqual([2, 1]);
  expect(await enc.countAsync("abb")).toBe(2);
  expect(await enc.decodeAsync(tokens)).toBe("abb");
});

test("sync BPE helpers do not silently fall back when ranks are configured", async () => {
  const wasmPath = resolve(process.cwd(), "zig-out/bin/turbotoken.wasm");
  if (!existsSync(wasmPath)) {
    return;
  }

  const rankPayload = new TextEncoder().encode("YQ== 0\nYg== 1\nYWI= 2\n\n");
  clearWasmCache();
  const enc = getEncoding("o200k_base", {
    backend: "wasm",
    wasm: { wasmPath, forceReload: true },
    rankPayload,
  });

  expect(() => enc.encode("abb")).toThrow(/loaded BPE backend/);

  await enc.ready();
  expect(enc.encode("abb")).toEqual([2, 1]);
  expect(enc.count("abb")).toBe(2);
  expect(enc.decode([2, 1])).toBe("abb");
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
