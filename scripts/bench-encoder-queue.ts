#!/usr/bin/env bun
import { runBench } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable, runShell } from "./_lib";

ensureFixtures();
const python = pythonExecutable();

function countCommand(mode: "hybrid" | "full-bucket"): string {
  return `TURBOTOKEN_ENCODER_QUEUE=${mode} ${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;from turbotoken._native import get_native_bridge;enc=get_encoding('o200k_base');enc.load_mergeable_ranks();bridge=get_native_bridge();assert bridge.available,bridge.error;text=pathlib.Path('bench/fixtures/english-100kb.txt').read_text().encode('utf-8');count=bridge.count_bpe_from_ranks(enc._rank_payload_cache,text);assert count is not None"`;
}

function encodeCommand(mode: "hybrid" | "full-bucket"): string {
  return `TURBOTOKEN_ENCODER_QUEUE=${mode} ${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;from turbotoken._native import get_native_bridge;enc=get_encoding('o200k_base');enc.load_mergeable_ranks();bridge=get_native_bridge();assert bridge.available,bridge.error;text=pathlib.Path('bench/fixtures/english-100kb.txt').read_text().encode('utf-8');tokens=bridge.encode_bpe_from_ranks(enc._rank_payload_cache,text);assert tokens is not None"`;
}

const commands = [
  { name: "hybrid-count-bpe-100kb", command: countCommand("hybrid") },
  { name: "full-bucket-count-bpe-100kb", command: countCommand("full-bucket") },
  { name: "hybrid-encode-bpe-100kb", command: encodeCommand("hybrid") },
  { name: "full-bucket-encode-bpe-100kb", command: encodeCommand("full-bucket") },
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
  console.warn("tiktoken is not installed; queue benchmark will include only turbotoken commands.");
}

process.exit(
  runBench({
    name: "bench-encoder-queue",
    commands,
    metadata: {
      fixture: "bench/fixtures/english-100kb.txt",
      includesTiktoken: tiktokenCheck.code === 0,
      note: "native rank-based scalar encode/count path with queue mode selector",
      env: "TURBOTOKEN_ENCODER_QUEUE=hybrid|full-bucket",
    },
  }),
);
