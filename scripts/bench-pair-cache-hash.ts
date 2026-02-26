#!/usr/bin/env bun
import { runBench } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable, runShell } from "./_lib";

ensureFixtures();
const python = pythonExecutable();

function countCommand(hash: "rapidhash" | "crc32"): string {
  return `TURBOTOKEN_PAIR_CACHE_HASH=${hash} ${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;from turbotoken._native import get_native_bridge;enc=get_encoding('o200k_base');enc.load_mergeable_ranks();payload=enc._ensure_rank_payload();bridge=get_native_bridge();assert bridge.available,bridge.error;text=pathlib.Path('bench/fixtures/english-100kb.txt').read_text().encode('utf-8');count=bridge.count_bpe_from_ranks(payload,text);assert count is not None"`;
}

function encodeCommand(hash: "rapidhash" | "crc32"): string {
  return `TURBOTOKEN_PAIR_CACHE_HASH=${hash} ${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;from turbotoken._native import get_native_bridge;enc=get_encoding('o200k_base');enc.load_mergeable_ranks();payload=enc._ensure_rank_payload();bridge=get_native_bridge();assert bridge.available,bridge.error;text=pathlib.Path('bench/fixtures/english-100kb.txt').read_text().encode('utf-8');tokens=bridge.encode_bpe_from_ranks(payload,text);assert tokens is not None"`;
}

const commands = [
  { name: "rapidhash-count-bpe-100kb", command: countCommand("rapidhash") },
  { name: "crc32-count-bpe-100kb", command: countCommand("crc32") },
  { name: "rapidhash-encode-bpe-100kb", command: encodeCommand("rapidhash") },
  { name: "crc32-encode-bpe-100kb", command: encodeCommand("crc32") },
];

const tiktokenCheck = runShell(
  `${python} -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec('tiktoken') else 1)"`,
  { allowFailure: true },
);

if (tiktokenCheck.code === 0) {
  commands.push({
    name: "tiktoken-encode-100kb",
    command:
      `${python} -c "import pathlib,tiktoken;text=pathlib.Path('bench/fixtures/english-100kb.txt').read_text();tiktoken.get_encoding('o200k_base').encode(text)"`,
  });
} else {
  console.warn("tiktoken is not installed; hash benchmark will include only turbotoken commands.");
}

process.exit(
  runBench({
    name: "bench-pair-cache-hash",
    commands,
    metadata: {
      fixture: "bench/fixtures/english-100kb.txt",
      includesTiktoken: tiktokenCheck.code === 0,
      note: "native rank-based scalar encode/count path with hash selector",
      env: "TURBOTOKEN_PAIR_CACHE_HASH=rapidhash|crc32",
    },
  }),
);
