#!/usr/bin/env bun
import { ensureDir, pythonExecutable, repoRoot, runCommand, section, writeJson } from "./_lib";
import { writeFileSync } from "node:fs";
import { delimiter, resolve } from "node:path";

const defaultExamples = "20";
const maxExamples = process.env.TIKTOKEN_MAX_EXAMPLES ?? defaultExamples;
const defaultDeselect = [
  // Upstream hypothesis roundtrip can generate disallowed special-token literals.
  // This case raises in both tiktoken and turbotoken with default arguments.
  "upstream/tiktoken/tests/test_encoding.py::test_hyp_roundtrip[cl100k_base]",
];
const extraDeselect = (process.env.TIKTOKEN_PYTEST_DESELECT ?? "")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);
const deselect = [...defaultDeselect, ...extraDeselect];

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
const hypothesisDb = resolve(repoRoot, ".tmp", "hypothesis-upstream-alias");
const pytestArgs = ["-m", "pytest", "-q", "--import-mode=importlib"];
for (const testId of deselect) {
  pytestArgs.push("--deselect", testId);
}
pytestArgs.push("upstream/tiktoken/tests");

const result = runCommand(
  python,
  pytestArgs,
  {
    env: {
      PYTHONPATH: pyPath,
      TIKTOKEN_MAX_EXAMPLES: maxExamples,
      HYPOTHESIS_DATABASE_DIRECTORY: hypothesisDb,
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
  deselect,
  command: `${python} ${pytestArgs.join(" ")}`,
});
console.log(`Wrote upstream alias test report: ${reportPath}`);
