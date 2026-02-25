#!/usr/bin/env bun
import { runBench } from "./_bench";
import { pythonExecutable } from "./_lib";

const python = pythonExecutable();
const command =
  `${python} -c "import sys;sys.path.insert(0,'python');import turbotoken;turbotoken.get_encoding('o200k_base').encode('hello world')"`;

process.exit(
  runBench({
    name: "bench-startup",
    commands: [{ name: "python-import-and-first-encode", command }],
    metadata: { workload: "import + first encode('hello world')" },
  }),
);
