#!/usr/bin/env bun
import { runBench } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable, runShell } from "./_lib";

ensureFixtures();
const python = pythonExecutable();

const commands = [
  {
    name: "turbotoken-encode-100kb",
    command:
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;text=pathlib.Path('bench/fixtures/english-100kb.txt').read_text();get_encoding('o200k_base').encode(text)"`,
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
  console.warn("tiktoken is not installed; comparison will include only turbotoken.");
}

process.exit(
  runBench({
    name: "bench-comparison",
    commands,
    metadata: {
      fixture: "bench/fixtures/english-100kb.txt",
      includesTiktoken: tiktokenCheck.code === 0,
    },
  }),
);
