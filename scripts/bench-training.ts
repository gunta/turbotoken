#!/usr/bin/env bun
import { existsSync } from "node:fs";
import { basename } from "node:path";
import { ensureFixtures } from "./_fixtures";
import { runBench, type BenchCommand } from "./_bench";
import { benchSpeedProfile, pythonExecutable, resolvePath, runShell } from "./_lib";

ensureFixtures();
const python = process.env.TURBOTOKEN_BENCH_PYTHON?.trim() || pythonExecutable();
const speedProfile = benchSpeedProfile();

const include10mb = ["1", "true", "yes", "on"].includes(
  (process.env.TURBOTOKEN_TRAIN_INCLUDE_10MB ?? "").trim().toLowerCase(),
);
const fixturePaths: string[] = process.env.TURBOTOKEN_TRAIN_FIXTURE?.trim()
  ? [resolvePath(process.env.TURBOTOKEN_TRAIN_FIXTURE.trim())]
  : speedProfile === "fast"
    ? [resolvePath("bench/fixtures/english-100kb.txt")]
    : [resolvePath("bench/fixtures/english-100kb.txt"), resolvePath("bench/fixtures/english-1mb.txt")];
if (include10mb) {
  fixturePaths.push(resolvePath("bench/fixtures/english-10mb.txt"));
}
const uniqueFixturePaths = [...new Set(fixturePaths)];
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
  return `TURBOTOKEN_NATIVE_TRAIN_THREADS=8 TURBOTOKEN_TRAIN_FIXTURE='${path}' ${python} -c "import ctypes,os,pathlib,platform;data=pathlib.Path(os.environ['TURBOTOKEN_TRAIN_FIXTURE']).read_bytes();lib_candidates=[];is_win=(os.name=='nt');suffix='dylib' if platform.system()=='Darwin' else ('dll' if is_win else 'so');primary=('turbotoken.'+suffix) if is_win else ('libturbotoken.'+suffix);lib_candidates.append(pathlib.Path('zig-out/lib')/primary);lib_candidates.append(pathlib.Path('wrappers/python/turbotoken/.libs')/primary);lib=None\nfor cand in lib_candidates:\n    if cand.exists():\n        lib=ctypes.CDLL(str(cand));\n        break\nassert lib is not None, lib_candidates;fn=lib.turbotoken_train_bpe_ascii_o200k;fn.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint32,ctypes.c_uint32,ctypes.POINTER(ctypes.c_uint32),ctypes.c_size_t];fn.restype=ctypes.c_long;cap=max(1,(${vocabSize}-256)*3);out=(ctypes.c_uint32*cap)();buf=ctypes.create_string_buffer(data);written=fn(ctypes.cast(buf,ctypes.c_void_p),len(data),${vocabSize},${minFrequency},out,cap);assert written>=1"`;
}

function commandForTurbotokenTrainingPythonFallback(path: string): string {
  return `TURBOTOKEN_TRAINING_BACKEND=python TURBOTOKEN_NATIVE_TRAINING_DISABLE=1 TURBOTOKEN_TRAIN_FIXTURE='${path}' ${python} -c "import os,pathlib;from turbotoken.training import train_mergeable_ranks_from_iterator;text=pathlib.Path(os.environ['TURBOTOKEN_TRAIN_FIXTURE']).read_text();_,ranks=train_mergeable_ranks_from_iterator([text],vocab_size=${vocabSize},pattern=None,min_frequency=${minFrequency});assert len(ranks)>=256"`;
}

function commandForMinbpeTraining(path: string): string {
  const maybePath = existsSync(minbpeLocalPath)
    ? `import sys;sys.path.insert(0,'${minbpeLocalPath}');`
    : "";
  return `TURBOTOKEN_TRAIN_FIXTURE='${path}' ${python} -c "import os,pathlib,sys,types;sys.modules.setdefault('tiktoken', types.ModuleType('tiktoken'));${maybePath}from minbpe import RegexTokenizer;text=pathlib.Path(os.environ['TURBOTOKEN_TRAIN_FIXTURE']).read_text();tok=RegexTokenizer();tok.train(text,${vocabSize});assert len(tok.vocab)>=256"`;
}

function commandForRustbpeTraining(path: string): string {
  return `TURBOTOKEN_TRAIN_FIXTURE='${path}' ${python} -c "import os,pathlib,rustbpe;text=pathlib.Path(os.environ['TURBOTOKEN_TRAIN_FIXTURE']).read_text();tok=rustbpe.Tokenizer();tok.train_from_iterator([text],vocab_size=${vocabSize});assert tok.vocab_size>=256"`;
}

const commands: BenchCommand[] = [];
for (const fixturePath of uniqueFixturePaths) {
  const fixtureLabel = basename(fixturePath, ".txt");
  commands.push({
    name: `python-train-${fixtureLabel}-turbotoken-native-v${vocabSize}`,
    command: commandForTurbotokenTraining(fixturePath),
  });
}

const smallestFixturePath = uniqueFixturePaths[0] ?? resolvePath("bench/fixtures/english-100kb.txt");
const smallestFixtureLabel = basename(smallestFixturePath, ".txt");
commands.push({
  name: `python-train-${smallestFixtureLabel}-turbotoken-py-fallback-v${vocabSize}`,
  command: commandForTurbotokenTrainingPythonFallback(smallestFixturePath),
});

if (availability.minbpe) {
  commands.push({
    name: `python-train-${smallestFixtureLabel}-minbpe-v${vocabSize}`,
    command: commandForMinbpeTraining(smallestFixturePath),
  });
}

if (availability.rustbpe) {
  commands.push({
    name: `python-train-${smallestFixtureLabel}-rustbpe-v${vocabSize}`,
    command: commandForRustbpeTraining(smallestFixturePath),
  });
}

const minRuns = speedProfile === "fast" ? 2 : 4;

const failures = runBench({
  name: "bench-training-python",
  commands,
  warmup: 1,
  minRuns,
  metadata: {
    fixturePaths: uniqueFixturePaths,
    vocabSize,
    minFrequency,
    speedProfile,
    availability,
    minbpeLocalPath: existsSync(minbpeLocalPath) ? minbpeLocalPath : null,
    note: "Training benchmark compares tokenizer training speed. Full profile includes 100KB and 1MB native rows; optional 10MB row can be enabled with TURBOTOKEN_TRAIN_INCLUDE_10MB=1. GPU training path is not implemented yet.",
  },
});

process.exit(failures);
