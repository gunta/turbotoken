#!/usr/bin/env bun
import { runBench } from "./_bench";
import { ensureFixtures } from "./_fixtures";

ensureFixtures();

const command =
  "python3 -c \"import json,pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;tokens=json.loads(pathlib.Path('bench/fixtures/english-100kb.tokens.json').read_text());get_encoding('o200k_base').decode(tokens)\"";

process.exit(
  runBench({
    name: "bench-decode",
    commands: [{ name: "turbotoken-decode-100kb-equivalent", command }],
    metadata: {
      fixture: "bench/fixtures/english-100kb.tokens.json",
      encoding: "o200k_base",
      note: "Token fixture currently reflects UTF-8 byte placeholder tokens.",
    },
  }),
);
