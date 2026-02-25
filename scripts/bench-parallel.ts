#!/usr/bin/env bun
import { runBench } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable } from "./_lib";

ensureFixtures();
const python = pythonExecutable();

const command =
  `${python} -c "import concurrent.futures,pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;text=pathlib.Path('bench/fixtures/english-10kb.txt').read_text();enc=get_encoding('o200k_base');pool=concurrent.futures.ThreadPoolExecutor(max_workers=4);list(pool.map(lambda _: enc.count(text), range(512)));pool.shutdown(wait=True)"`;

process.exit(
  runBench({
    name: "bench-parallel",
    commands: [{ name: "threadpool-count-512-items", command }],
    metadata: {
      workers: 4,
      items: 512,
      fixture: "bench/fixtures/english-10kb.txt",
      encoding: "o200k_base",
    },
  }),
);
