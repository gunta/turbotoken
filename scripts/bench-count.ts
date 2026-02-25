#!/usr/bin/env bun
import { runBench } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable } from "./_lib";

ensureFixtures();
const python = pythonExecutable();

const command =
  `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;text=pathlib.Path('bench/fixtures/english-100kb.txt').read_text();get_encoding('o200k_base').count(text)"`;

process.exit(
  runBench({
    name: "bench-count",
    commands: [{ name: "turbotoken-count-100kb", command }],
    metadata: { fixture: "bench/fixtures/english-100kb.txt", encoding: "o200k_base" },
  }),
);
