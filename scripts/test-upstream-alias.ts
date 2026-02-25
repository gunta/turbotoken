#!/usr/bin/env bun
import { ensureDir, pythonExecutable, repoRoot, runCommand, section, writeJson } from "./_lib";
import { writeFileSync } from "node:fs";
import { delimiter, resolve } from "node:path";

const defaultExamples = "20";
const maxExamples = process.env.TIKTOKEN_MAX_EXAMPLES ?? defaultExamples;

section("Prepare tiktoken alias shim");
const shimDir = resolve(repoRoot, ".tmp", "tiktoken_shim", "tiktoken");
ensureDir(shimDir);
writeFileSync(
  resolve(shimDir, "__init__.py"),
  [
    "from turbotoken import *",
    "from turbotoken import __version__",
    "",
  ].join("\n"),
  "utf8",
);

section("Run upstream tiktoken public tests against turbotoken alias");
const python = pythonExecutable();
const pyPath = [resolve(repoRoot, ".tmp", "tiktoken_shim"), resolve(repoRoot, "python")].join(delimiter);

const result = runCommand(
  python,
  ["-m", "pytest", "-q", "--import-mode=importlib", "upstream/tiktoken/tests"],
  {
    env: {
      PYTHONPATH: pyPath,
      TIKTOKEN_MAX_EXAMPLES: maxExamples,
    },
  },
);

process.stdout.write(result.stdout);
if (result.stderr.trim()) {
  process.stderr.write(result.stderr);
}

const reportPath = resolve(repoRoot, "bench", "results", `upstream-alias-${Date.now()}.json`);
writeJson(reportPath, {
  status: "ok",
  max_examples: maxExamples,
  command: `${python} -m pytest -q --import-mode=importlib upstream/tiktoken/tests`,
});
console.log(`Wrote upstream alias test report: ${reportPath}`);
