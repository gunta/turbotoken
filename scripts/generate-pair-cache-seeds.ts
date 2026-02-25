#!/usr/bin/env bun
import { gunzipSync } from "node:zlib";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { ensureDir, resolvePath } from "./_lib";

interface RankEntry {
  rank: number;
  token: Buffer;
}

interface SeedPair {
  left: number;
  right: number;
  rank: number;
}

interface SeedSetSpec {
  name: string;
  sourcePath: string;
  maxRank: number;
  maxPairs: number;
}

const FNV_OFFSET_BASIS = 0xcbf29ce484222325n;
const FNV_PRIME = 0x100000001b3n;
const U64_MASK = 0xffffffffffffffffn;
const FINGERPRINT_TOKEN_LIMIT = 1024;

const seedSpecs: SeedSetSpec[] = [
  {
    name: "cl100k_base",
    sourcePath: resolvePath("upstream", "rs-bpe", "bpe-openai", "data", "cl100k_base.tiktoken.gz"),
    maxRank: 32768,
    maxPairs: 65536,
  },
  {
    name: "o200k_base",
    sourcePath: resolvePath("upstream", "rs-bpe", "bpe-openai", "data", "o200k_base.tiktoken.gz"),
    maxRank: 32768,
    maxPairs: 65536,
  },
];

function fnv1aUpdate(hash: bigint, bytes: Uint8Array): bigint {
  let next = hash;
  for (const byte of bytes) {
    next ^= BigInt(byte);
    next = (next * FNV_PRIME) & U64_MASK;
  }
  return next;
}

function fnv1aU32(hash: bigint, value: number): bigint {
  const bytes = new Uint8Array(4);
  bytes[0] = value & 0xff;
  bytes[1] = (value >>> 8) & 0xff;
  bytes[2] = (value >>> 16) & 0xff;
  bytes[3] = (value >>> 24) & 0xff;
  return fnv1aUpdate(hash, bytes);
}

function parseRankFile(sourcePath: string): RankEntry[] {
  const payload = gunzipSync(readFileSync(sourcePath)).toString("utf8");
  const entries: RankEntry[] = [];
  const seenRanks = new Set<number>();
  const seenTokens = new Set<string>();

  for (const rawLine of payload.split("\n")) {
    const line = rawLine.trim();
    if (line.length === 0) {
      continue;
    }

    const firstWhitespace = line.search(/\s/);
    if (firstWhitespace <= 0 || firstWhitespace === line.length - 1) {
      throw new Error(`invalid line in ${sourcePath}: ${line}`);
    }

    const tokenB64 = line.slice(0, firstWhitespace).trim();
    const rankText = line.slice(firstWhitespace + 1).trim();
    const rank = Number.parseInt(rankText, 10);
    if (!Number.isFinite(rank) || rank < 0 || !Number.isInteger(rank)) {
      throw new Error(`invalid rank in ${sourcePath}: ${rankText}`);
    }

    const token = Buffer.from(tokenB64, "base64");
    const tokenKey = token.toString("hex");
    if (seenRanks.has(rank)) {
      throw new Error(`duplicate rank ${rank} in ${sourcePath}`);
    }
    if (seenTokens.has(tokenKey)) {
      throw new Error(`duplicate token in ${sourcePath}`);
    }

    seenRanks.add(rank);
    seenTokens.add(tokenKey);
    entries.push({ rank, token });
  }

  entries.sort((a, b) => a.rank - b.rank);
  return entries;
}

function rankFingerprint(entries: RankEntry[]): bigint {
  let hash = FNV_OFFSET_BASIS;
  const limit = Math.min(FINGERPRINT_TOKEN_LIMIT, entries.length);
  for (let idx = 0; idx < limit; idx += 1) {
    const entry = entries[idx];
    hash = fnv1aU32(hash, entry.rank >>> 0);
    hash = fnv1aU32(hash, entry.token.length >>> 0);
    hash = fnv1aUpdate(hash, entry.token);
  }
  return hash;
}

function deriveSeedPairs(entries: RankEntry[], maxRank: number, maxPairs: number): SeedPair[] {
  const tokenToRank = new Map<string, number>();
  for (const entry of entries) {
    tokenToRank.set(entry.token.toString("hex"), entry.rank);
  }

  const pairs = new Map<string, SeedPair>();

  for (const entry of entries) {
    if (entry.rank > maxRank || entry.token.length < 2) {
      continue;
    }

    for (let splitAt = 1; splitAt < entry.token.length; splitAt += 1) {
      const leftRank = tokenToRank.get(entry.token.subarray(0, splitAt).toString("hex"));
      const rightRank = tokenToRank.get(entry.token.subarray(splitAt).toString("hex"));
      if (leftRank === undefined || rightRank === undefined) {
        continue;
      }

      const key = `${leftRank}:${rightRank}`;
      const existing = pairs.get(key);
      if (existing === undefined || entry.rank < existing.rank) {
        pairs.set(key, {
          left: leftRank,
          right: rightRank,
          rank: entry.rank,
        });
      }
    }
  }

  const sorted = [...pairs.values()].sort((a, b) => {
    if (a.rank !== b.rank) {
      return a.rank - b.rank;
    }
    if (a.left !== b.left) {
      return a.left - b.left;
    }
    return a.right - b.right;
  });

  return sorted.slice(0, maxPairs);
}

function zigIdentifier(name: string): string {
  return name.replace(/[^a-zA-Z0-9]/g, "_");
}

function zigU64Literal(value: bigint): string {
  return `0x${value.toString(16)}`;
}

function renderSeedPairsConstant(constName: string, pairs: SeedPair[]): string {
  const lines = pairs.map(
    (pair) => `    .{ .left = ${pair.left}, .right = ${pair.right}, .rank = ${pair.rank} },`,
  );
  return [`const ${constName} = [_]SeedPair{`, ...lines, "};"].join("\n");
}

function main(): void {
  const missing = seedSpecs.find((spec) => !existsSync(spec.sourcePath));
  if (missing) {
    throw new Error(
      `missing source rank file: ${missing.sourcePath}\nrun: bun run sync:upstream`,
    );
  }

  const sets = seedSpecs.map((spec) => {
    const entries = parseRankFile(spec.sourcePath);
    return {
      spec,
      fingerprint: rankFingerprint(entries),
      pairs: deriveSeedPairs(entries, spec.maxRank, spec.maxPairs),
      vocabSize: entries.length,
    };
  });

  const generatedPath = resolvePath("src", "generated", "pair_cache_seeds.zig");
  ensureDir(dirname(generatedPath));

  const constants = sets.map((set) =>
    renderSeedPairsConstant(`${zigIdentifier(set.spec.name)}_pairs`, set.pairs),
  );

  const seedSetLines = sets.map(
    (set) =>
      [
        "    .{",
        `        .name = "${set.spec.name}",`,
        `        .fingerprint = ${zigU64Literal(set.fingerprint)},`,
        `        .pairs = ${zigIdentifier(set.spec.name)}_pairs[0..],`,
        "    },",
      ].join("\n"),
  );

  const metadata = sets.map(
    (set) =>
      `// ${set.spec.name}: vocab=${set.vocabSize}, max_rank=${set.spec.maxRank}, pair_count=${set.pairs.length}, source=${set.spec.sourcePath}`,
  );

  const output = [
    "// AUTO-GENERATED by scripts/generate-pair-cache-seeds.ts",
    "// Do not edit manually.",
    ...metadata,
    "",
    "pub const fingerprint_token_limit: u32 = " + `${FINGERPRINT_TOKEN_LIMIT};`,
    "",
    "pub const SeedPair = struct {",
    "    left: u32,",
    "    right: u32,",
    "    rank: u32,",
    "};",
    "",
    "pub const SeedSet = struct {",
    "    name: []const u8,",
    "    fingerprint: u64,",
    "    pairs: []const SeedPair,",
    "};",
    "",
    ...constants,
    "",
    "pub const seed_sets = [_]SeedSet{",
    ...seedSetLines,
    "};",
    "",
  ].join("\n");

  writeFileSync(generatedPath, output, "utf8");
  console.log(`wrote ${generatedPath}`);
  for (const set of sets) {
    console.log(`${set.spec.name}: ${set.pairs.length} seed pairs`);
  }
}

main();
