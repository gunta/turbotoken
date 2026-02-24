#!/usr/bin/env bun
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { ensureDir, resolvePath } from "./_lib";

const FIXTURES_DIR = resolvePath("bench", "fixtures");

function repeatToSize(seed: string, bytes: number): string {
  if (bytes <= 0) {
    return "";
  }

  let out = "";
  while (Buffer.byteLength(out, "utf8") < bytes) {
    out += seed;
  }

  const buffer = Buffer.from(out, "utf8");
  return buffer.subarray(0, bytes).toString("utf8");
}

function writeFixture(path: string, content: string, force: boolean): void {
  if (!force && existsSync(path)) {
    return;
  }
  writeFileSync(path, content, "utf8");
}

function createDecodeTokensFixture(force: boolean): void {
  const sourcePath = resolve(FIXTURES_DIR, "english-100kb.txt");
  const tokensPath = resolve(FIXTURES_DIR, "english-100kb.tokens.json");

  if (!force && existsSync(tokensPath)) {
    return;
  }

  const text = readFileSync(sourcePath, "utf8");
  const tokens = Array.from(Buffer.from(text, "utf8"));
  writeFileSync(tokensPath, `${JSON.stringify(tokens)}\n`, "utf8");
}

export function ensureFixtures(force = false): void {
  ensureDir(FIXTURES_DIR);

  const englishSeed =
    "Tokenizer throughput matters for coding agents and context-window management.\n" +
    "turbotoken is still scaffold-stage in this repository, so benchmarks are placeholders.\n";

  const codeSeed =
    "def fibonacci(n: int) -> int:\n" +
    "    if n < 2:\n" +
    "        return n\n" +
    "    a, b = 0, 1\n" +
    "    for _ in range(n):\n" +
    "        a, b = b, a + b\n" +
    "    return a\n\n";

  const cjkSeed =
    "\u4eca\u65e5\u306f\u826f\u3044\u5929\u6c17\u3067\u3059\u306d\u3002" +
    "\u660e\u65e5\u306e\u30e2\u30c7\u30eb\u8a55\u4fa1\u3092\u6e96\u5099\u3057\u3066\u3044\u307e\u3059\u3002\n";
  const emojiSeed =
    "Debugging \ud83e\uddea, profiling \ud83d\ude80, and shipping \u2705 with calm iteration.\n";

  writeFixture(resolve(FIXTURES_DIR, "english-1kb.txt"), repeatToSize(englishSeed, 1024), force);
  writeFixture(resolve(FIXTURES_DIR, "english-10kb.txt"), repeatToSize(englishSeed, 10 * 1024), force);
  writeFixture(resolve(FIXTURES_DIR, "english-100kb.txt"), repeatToSize(englishSeed, 100 * 1024), force);
  writeFixture(resolve(FIXTURES_DIR, "english-1mb.txt"), repeatToSize(englishSeed, 1024 * 1024), force);
  writeFixture(resolve(FIXTURES_DIR, "code-50kb.py"), repeatToSize(codeSeed, 50 * 1024), force);
  writeFixture(resolve(FIXTURES_DIR, "cjk-10kb.txt"), repeatToSize(cjkSeed, 10 * 1024), force);
  writeFixture(resolve(FIXTURES_DIR, "emoji-10kb.txt"), repeatToSize(emojiSeed, 10 * 1024), force);

  createDecodeTokensFixture(force);
}
