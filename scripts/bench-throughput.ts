#!/usr/bin/env bun
import { runBench } from "./_bench";
import { ensureFixtures } from "./_fixtures";

ensureFixtures();

function countCommand(file: string): string {
  return `python3 -c \"import pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;text=pathlib.Path('${file}').read_text();get_encoding('o200k_base').count(text)\"`;
}

process.exit(
  runBench({
    name: "bench-throughput",
    commands: [
      { name: "count-1kb", command: countCommand("bench/fixtures/english-1kb.txt") },
      { name: "count-10kb", command: countCommand("bench/fixtures/english-10kb.txt") },
      { name: "count-100kb", command: countCommand("bench/fixtures/english-100kb.txt") },
    ],
    metadata: { encoding: "o200k_base", operation: "count" },
  }),
);
