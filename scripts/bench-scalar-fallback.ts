#!/usr/bin/env bun
import { runBench } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable, runShell } from "./_lib";

ensureFixtures();
const python = pythonExecutable();

const commands = [
  {
    name: "turbotoken-native-count-bpe-100kb",
    command:
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;from turbotoken._rank_files import read_rank_file_native_payload;payload=read_rank_file_native_payload('o200k_base');bridge=get_native_bridge();assert bridge.available,bridge.error;text=pathlib.Path('bench/fixtures/english-100kb.txt').read_bytes();count=bridge.count_bpe_from_ranks(payload,text);assert count is not None"`,
  },
  {
    name: "turbotoken-native-encode-bpe-100kb",
    command:
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;from turbotoken._rank_files import read_rank_file_native_payload;payload=read_rank_file_native_payload('o200k_base');bridge=get_native_bridge();assert bridge.available,bridge.error;text=pathlib.Path('bench/fixtures/english-100kb.txt').read_bytes();tokens=bridge.encode_bpe_from_ranks(payload,text);assert tokens is not None"`,
  },
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
  console.warn("tiktoken is not installed; scalar benchmark will include only turbotoken commands.");
}

process.exit(
  runBench({
    name: "bench-scalar-fallback",
    commands,
    metadata: {
      fixture: "bench/fixtures/english-100kb.txt",
      includesTiktoken: tiktokenCheck.code === 0,
      note: "native rank-based scalar encode/count path",
    },
  }),
);
