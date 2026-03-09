#!/usr/bin/env bun
import { Buffer } from "node:buffer";
import { runBench } from "./_bench";
import { pythonExecutable } from "./_lib";

const python = pythonExecutable();
const targetBytes = 1_048_576;
const mediumPieces = [
  "Tokenizer",
  " throughput",
  " matters",
  " for",
  " coding",
  " agents",
  " and",
  " context",
  "-window",
  " management",
  " turbotoken",
  " still",
  " scaffold",
  "-stage",
  " this",
  " repository",
  " benchmarks",
  " are",
] as const;

const piecesPayload = Buffer.from(JSON.stringify(mediumPieces), "utf8").toString("base64");

function buildPythonCommand(operation: "encode" | "count"): string {
  const body =
    "import base64,json;" +
    `pieces=json.loads(base64.b64decode('${piecesPayload}'));` +
    `target=${targetBytes};` +
    "seed=''.join(pieces);" +
    "repeat=(target // len(seed)) + 1;" +
    "text=(seed * repeat)[:target];" +
    "from turbotoken import get_encoding;" +
    `enc=get_encoding('o200k_base');enc.${operation}(text)`;
  return `TURBOTOKEN_NATIVE_O200K_FULL_ENABLE=1 TURBOTOKEN_NATIVE_RANGE_BATCH_DISABLE=1 ${python} -c "${body}"`;
}

process.exit(
  runBench({
    name: "bench-medium-pieces",
    commands: [
      {
        name: "python-encode-medium-pieces-1mb-turbotoken",
        command: buildPythonCommand("encode"),
      },
      {
        name: "python-count-medium-pieces-1mb-turbotoken",
        command: buildPythonCommand("count"),
      },
    ],
    metadata: {
      encoding: "o200k_base",
      targetBytes,
      forceNativeO200kFull: true,
      disableRangeBatch: true,
      mediumPieces,
      note: "Synthetic 1 MiB ASCII corpus composed of common 4-12 byte o200k pretokenizer pieces from the english-1mb fixture.",
    },
  }),
);
