#!/usr/bin/env bun
import { runBench, type BenchCommand } from "./_bench";
import { pythonExecutable, runShell, section } from "./_lib";

function hasPythonModule(python: string, name: string): boolean {
  const result = runShell(
    `${python} -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec('${name}') else 1)"`,
    { allowFailure: true },
  );
  return result.code === 0;
}

const python = pythonExecutable();
const availability = {
  tiktoken: hasPythonModule(python, "tiktoken"),
  rs_bpe: hasPythonModule(python, "rs_bpe"),
  token_dagger:
    hasPythonModule(python, "token_dagger") || hasPythonModule(python, "tokendagger"),
};

const commands: BenchCommand[] = [
  {
    name: "python-startup-turbotoken",
    command:
      `${python} -c "import sys;sys.path.insert(0,'python');import turbotoken;turbotoken.get_encoding('o200k_base').encode('hello')"`,
  },
  {
    name: "python-startup-turbotoken-cli",
    command:
      `${python} -m turbotoken.cli encode hello --encoding o200k_base >/dev/null`,
  },
];

if (availability.tiktoken) {
  commands.push({
    name: "python-startup-tiktoken",
    command:
      `${python} -c "import tiktoken;tiktoken.get_encoding('o200k_base').encode('hello')"`,
  });
}

if (availability.rs_bpe) {
  commands.push({
    name: "python-startup-rs-bpe",
    command:
      `${python} -c "from rs_bpe.bpe import openai;openai.o200k_base().encode('hello')"`,
  });
}

if (availability.token_dagger) {
  commands.push({
    name: "python-startup-token-dagger",
    command:
      `${python} -c "import importlib.util\nif importlib.util.find_spec('token_dagger'):\n import token_dagger as td\n enc=td.get_encoding('o200k_base')\nelse:\n import tiktoken,tokendagger as td\n base=tiktoken.get_encoding('o200k_base')\n enc=td.Encoding('o200k_base',pat_str=base._pat_str,mergeable_ranks=base._mergeable_ranks,special_tokens=base._special_tokens)\nenc.encode('hello')"`,
  });
}

section("Startup benchmark (cold process)");
const coldFailures = runBench({
  name: "bench-startup-cold",
  commands,
  warmup: 0,
  minRuns: 30,
  metadata: {
    mode: "cold",
    workload: "process startup + first encode('hello')",
    availability,
  },
});

section("Startup benchmark (warm process)");
const warmFailures = runBench({
  name: "bench-startup-warm",
  commands,
  warmup: 10,
  minRuns: 30,
  metadata: {
    mode: "warm",
    workload: "same command measured after hyperfine warmup runs",
    availability,
  },
});

process.exit(coldFailures + warmFailures);
