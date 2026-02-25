#!/usr/bin/env bun
import { pythonExecutable, resolvePath, section, writeJson } from "./_lib";
import { ensureFixtures } from "./_fixtures";

ensureFixtures();
section("Memory benchmark");
const python = pythonExecutable();

const pythonSnippet =
  "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;text=pathlib.Path('bench/fixtures/english-1mb.txt').read_text();get_encoding('o200k_base').encode(text)";

const timeFlag = process.platform === "darwin" ? "-l" : "-v";
const result = Bun.spawnSync({
  cmd: ["/usr/bin/time", timeFlag, python, "-c", pythonSnippet],
  cwd: resolvePath(),
  stdout: "pipe",
  stderr: "pipe",
});

const stderr = Buffer.from(result.stderr).toString("utf8");
const stdout = Buffer.from(result.stdout).toString("utf8");

const macMatch = stderr.match(/(\d+)\s+maximum resident set size/);
const linuxMatch = stderr.match(/Maximum resident set size \(kbytes\):\s+(\d+)/);
const maxRssKb = macMatch ? Number(macMatch[1]) / 1024 : linuxMatch ? Number(linuxMatch[1]) : null;

const outputPath = resolvePath("bench", "results", `bench-ram-${Date.now()}.json`);
writeJson(outputPath, {
  tool: "/usr/bin/time",
  generatedAt: new Date().toISOString(),
  platform: process.platform,
  exitCode: result.exitCode,
  maxRssKb,
  command: `${python} -c <snippet>`,
  stdout,
  stderr,
});

if (result.exitCode !== 0) {
  console.error(stderr.trim());
  process.exit(result.exitCode ?? 1);
}

console.log(`Wrote RAM benchmark record: ${outputPath}`);
process.exit(0);
