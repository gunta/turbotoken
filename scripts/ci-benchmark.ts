#!/usr/bin/env bun
import { runCommand, section } from "./_lib";

const scripts = [
  "scripts/generate-fixture.ts",
  "scripts/bench-startup.ts",
  "scripts/bench-count.ts",
  "scripts/bench-encode.ts",
  "scripts/generate-charts.ts",
];

let failures = 0;
for (const script of scripts) {
  section(`CI benchmark: ${script}`);
  const result = runCommand("bun", ["run", script], { allowFailure: true });
  if (result.stdout.trim().length > 0) {
    console.log(result.stdout.trim());
  }
  if (result.stderr.trim().length > 0) {
    console.error(result.stderr.trim());
  }
  if (result.code !== 0) {
    failures += 1;
  }
}

process.exit(failures === 0 ? 0 : 1);
