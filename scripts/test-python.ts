#!/usr/bin/env bun
import { ensurePythonDevEnvironment, runCommand, section } from "./_lib";

section("Running python-tests");
const python = ensurePythonDevEnvironment();
const result = runCommand(python, ["-m", "pytest", "-q"]);

if (result.stdout.trim().length > 0) {
  process.stdout.write(result.stdout);
}
if (result.stderr.trim().length > 0) {
  process.stderr.write(result.stderr);
}
