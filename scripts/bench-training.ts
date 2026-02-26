#!/usr/bin/env bun
import { existsSync } from "node:fs";
import { basename } from "node:path";
import { ensureFixtures } from "./_fixtures";
import { runBench, type BenchCommand } from "./_bench";
import { pythonExecutable, resolvePath, runShell } from "./_lib";

ensureFixtures();
const python = process.env.TURBOTOKEN_BENCH_PYTHON?.trim() || pythonExecutable();

const fixturePath = process.env.TURBOTOKEN_TRAIN_FIXTURE?.trim()
  ? resolvePath(process.env.TURBOTOKEN_TRAIN_FIXTURE.trim())
  : resolvePath("bench/fixtures/english-100kb.txt");
const fixtureLabel = basename(fixturePath, ".txt");
const vocabSize = Number.parseInt(process.env.TURBOTOKEN_TRAIN_VOCAB_SIZE ?? "320", 10);
const minFrequency = Number.parseInt(process.env.TURBOTOKEN_TRAIN_MIN_FREQUENCY ?? "2", 10);
const minbpeLocalPath = process.env.TURBOTOKEN_MINBPE_PATH?.trim() || "/tmp/minbpe";

function hasPythonModule(name: string): boolean {
  const result = runShell(
    `${python} -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec('${name}') else 1)"`,
    { allowFailure: true },
  );
  return result.code === 0;
}

const availability = {
  turbotoken: true,
  minbpe: hasPythonModule("minbpe") || existsSync(minbpeLocalPath),
  rustbpe: hasPythonModule("rustbpe"),
};

function commandForTurbotokenTraining(path: string): string {
  return `TURBOTOKEN_TRAINING_BACKEND=native TURBOTOKEN_TRAIN_FIXTURE='${path}' ${python} -c "import os,pathlib,sys;sys.path.insert(0,'python');from turbotoken.training import train_mergeable_ranks_from_iterator;text=pathlib.Path(os.environ['TURBOTOKEN_TRAIN_FIXTURE']).read_text();_,ranks=train_mergeable_ranks_from_iterator([text],vocab_size=${vocabSize},pattern=None,min_frequency=${minFrequency});assert len(ranks)>=256"`;
}

function commandForTurbotokenTrainingPythonFallback(path: string): string {
  return `TURBOTOKEN_TRAINING_BACKEND=python TURBOTOKEN_NATIVE_TRAINING_DISABLE=1 TURBOTOKEN_TRAIN_FIXTURE='${path}' ${python} -c "import os,pathlib,sys;sys.path.insert(0,'python');from turbotoken.training import train_mergeable_ranks_from_iterator;text=pathlib.Path(os.environ['TURBOTOKEN_TRAIN_FIXTURE']).read_text();_,ranks=train_mergeable_ranks_from_iterator([text],vocab_size=${vocabSize},pattern=None,min_frequency=${minFrequency});assert len(ranks)>=256"`;
}

function commandForMinbpeTraining(path: string): string {
  const maybePath = existsSync(minbpeLocalPath)
    ? `import sys;sys.path.insert(0,'${minbpeLocalPath}');`
    : "";
  return `TURBOTOKEN_TRAIN_FIXTURE='${path}' ${python} -c "import os,pathlib;${maybePath}from minbpe import RegexTokenizer;text=pathlib.Path(os.environ['TURBOTOKEN_TRAIN_FIXTURE']).read_text();tok=RegexTokenizer();tok.train(text,${vocabSize});assert len(tok.vocab)>=256"`;
}

function commandForRustbpeTraining(path: string): string {
  return `TURBOTOKEN_TRAIN_FIXTURE='${path}' ${python} -c "import os,pathlib,rustbpe;text=pathlib.Path(os.environ['TURBOTOKEN_TRAIN_FIXTURE']).read_text();tok=rustbpe.Tokenizer();tok.train_from_iterator([text],vocab_size=${vocabSize});assert tok.vocab_size>=256"`;
}

const commands: BenchCommand[] = [
  {
    name: `python-train-${fixtureLabel}-turbotoken-native-v${vocabSize}`,
    command: commandForTurbotokenTraining(fixturePath),
  },
  {
    name: `python-train-${fixtureLabel}-turbotoken-py-fallback-v${vocabSize}`,
    command: commandForTurbotokenTrainingPythonFallback(fixturePath),
  },
];

if (availability.minbpe) {
  commands.push({
    name: `python-train-${fixtureLabel}-minbpe-v${vocabSize}`,
    command: commandForMinbpeTraining(fixturePath),
  });
}

if (availability.rustbpe) {
  commands.push({
    name: `python-train-${fixtureLabel}-rustbpe-v${vocabSize}`,
    command: commandForRustbpeTraining(fixturePath),
  });
}

const failures = runBench({
  name: "bench-training-python",
  commands,
  warmup: 1,
  minRuns: 6,
  metadata: {
    fixturePath,
    vocabSize,
    minFrequency,
    availability,
    minbpeLocalPath: existsSync(minbpeLocalPath) ? minbpeLocalPath : null,
    note: "Training benchmark compares tokenizer training speed. turbotoken training is a new CPU incremental-pair-count implementation; GPU training path is not implemented yet.",
  },
});

process.exit(failures);
