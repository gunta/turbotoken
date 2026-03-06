import { createHash } from "node:crypto";
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { gunzipSync } from "node:zlib";

type EncodingName = "o200k_base" | "cl100k_base";

const REPO_ROOT = resolve(import.meta.dir, "..");
const OUTPUT_DIR = resolve(REPO_ROOT, "wrappers", "python", "turbotoken", "_data", "ranks");
const MAGIC = Buffer.from("TTKRBIN1", "ascii");
const VERSION = 1;
const FLAGS = 0;
const MISSING = 0xFFFFFFFF;

const SOURCES: Record<EncodingName, string> = {
  o200k_base: resolve(REPO_ROOT, "upstream", "rs-bpe", "bpe-openai", "data", "o200k_base.tiktoken.gz"),
  cl100k_base: resolve(REPO_ROOT, "upstream", "rs-bpe", "bpe-openai", "data", "cl100k_base.tiktoken.gz"),
};

function encodeU32(value: number): Buffer {
  const out = Buffer.allocUnsafe(4);
  out.writeUInt32LE(value, 0);
  return out;
}

function encodeU64(value: bigint): Buffer {
  const out = Buffer.allocUnsafe(8);
  out.writeBigUInt64LE(value, 0);
  return out;
}

function stableSourceFingerprint(payload: Buffer): bigint {
  const digest = createHash("sha256").update(payload).digest();
  return digest.readBigUInt64LE(0);
}

function buildNativePayload(source: Buffer): Buffer {
  const entries: Array<{ rank: number; token: Buffer }> = [];
  let maxRank = -1;

  for (const rawLine of source.toString("utf8").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line.length === 0) {
      continue;
    }

    const parts = line.split(/\s+/);
    if (parts.length !== 2) {
      throw new Error(`invalid rank line: ${line}`);
    }

    const [tokenB64, rankText] = parts;
    const rank = Number.parseInt(rankText, 10);
    if (!Number.isInteger(rank) || rank < 0 || rank > 0xFFFFFFFF) {
      throw new Error(`rank out of range: ${rankText}`);
    }

    const token = Buffer.from(tokenB64, "base64");
    entries.push({ rank, token });
    if (rank > maxRank) {
      maxRank = rank;
    }
  }

  const maxRankPlusOne = Math.max(0, maxRank + 1);
  const dense = new Array<Buffer | null>(maxRankPlusOne).fill(null);
  for (const entry of entries) {
    if (dense[entry.rank] !== null) {
      throw new Error(`duplicate rank: ${entry.rank}`);
    }
    dense[entry.rank] = entry.token;
  }

  const chunks: Buffer[] = [
    MAGIC,
    encodeU32(VERSION),
    encodeU32(FLAGS),
    encodeU64(BigInt(source.length)),
    encodeU64(stableSourceFingerprint(source)),
    encodeU32(entries.length),
    encodeU32(maxRankPlusOne),
  ];

  for (const token of dense) {
    if (token === null) {
      chunks.push(encodeU32(MISSING));
      continue;
    }
    chunks.push(encodeU32(token.length), token);
  }

  return Buffer.concat(chunks);
}

async function writeIfChanged(path: string, payload: Buffer): Promise<void> {
  await mkdir(dirname(path), { recursive: true });

  try {
    const existing = await readFile(path);
    if (existing.equals(payload)) {
      return;
    }
  } catch {
    // Missing file is fine.
  }

  await writeFile(path, payload);
}

async function main(): Promise<void> {
  await mkdir(OUTPUT_DIR, { recursive: true });

  for (const [name, sourcePath] of Object.entries(SOURCES) as Array<[EncodingName, string]>) {
    const compressed = await readFile(sourcePath);
    const source = gunzipSync(compressed);
    const native = buildNativePayload(source);
    const outputPath = resolve(OUTPUT_DIR, `${name}.tiktoken.native.bin`);

    await writeIfChanged(outputPath, native);

    const sourceStats = await stat(sourcePath);
    console.log(
      `${name}: ${sourcePath} (${sourceStats.size} B gz) -> ${outputPath} (${native.length} B native)`
    );
  }
}

await main();
