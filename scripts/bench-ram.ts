#!/usr/bin/env bun
import { acquireBenchmarkLock, pythonExecutable, resolvePath, runShell, section, writeJson } from "./_lib";
import { ensureFixtures } from "./_fixtures";

interface MemoryCommand {
  name: string;
  command: string;
}

interface MemorySample {
  run: number;
  exitCode: number;
  maxRssKb: number | null;
  stdout: string;
  stderr: string;
}

function hasPythonModule(python: string, name: string): boolean {
  const result = runShell(
    `${python} -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec('${name}') else 1)"`,
    { allowFailure: true },
  );
  return result.code === 0;
}

function hasBunModule(name: string): boolean {
  const result = runShell(
    `bun -e "import('${name}').then(()=>process.exit(0)).catch(()=>process.exit(1))"`,
    { allowFailure: true },
  );
  return result.code === 0;
}

function parseMaxRssKb(stderr: string): number | null {
  const macMatch = stderr.match(/(\d+)\s+maximum resident set size/);
  if (macMatch) {
    return Number(macMatch[1]) / 1024;
  }

  const linuxMatch = stderr.match(/Maximum resident set size \(kbytes\):\s+(\d+)/);
  if (linuxMatch) {
    return Number(linuxMatch[1]);
  }

  return null;
}

function median(values: number[]): number | null {
  if (values.length === 0) {
    return null;
  }
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

ensureFixtures();
section("Memory benchmark");
acquireBenchmarkLock({ label: "bench-ram" });
const python = pythonExecutable();
const runsRaw = process.env.TURBOTOKEN_RAM_RUNS?.trim();
const runs = runsRaw ? Math.max(1, Number.parseInt(runsRaw, 10) || 5) : 5;

const availability = {
  tiktoken: hasPythonModule(python, "tiktoken"),
  rs_bpe: hasPythonModule(python, "rs_bpe"),
  token_dagger:
    hasPythonModule(python, "token_dagger") || hasPythonModule(python, "tokendagger"),
  gpt_tokenizer: hasBunModule("gpt-tokenizer"),
};

const commands: MemoryCommand[] = [
  {
    name: "python-empty-baseline",
    command: `${python} -c "pass"`,
  },
  {
    name: "python-ram-turbotoken-encode-1mb",
    command:
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;text=pathlib.Path('bench/fixtures/english-1mb.txt').read_text();get_encoding('o200k_base').encode(text)"`,
  },
  {
    name: "python-ram-turbotoken-cli-encode-1mb",
    command:
      `${python} -m turbotoken.cli encode - --encoding o200k_base < bench/fixtures/english-1mb.txt >/dev/null`,
  },
];

if (availability.tiktoken) {
  commands.push({
    name: "python-ram-tiktoken-encode-1mb",
    command:
      `${python} -c "import pathlib,tiktoken;text=pathlib.Path('bench/fixtures/english-1mb.txt').read_text();tiktoken.get_encoding('o200k_base').encode(text)"`,
  });
}

if (availability.rs_bpe) {
  commands.push({
    name: "python-ram-rs-bpe-encode-1mb",
    command:
      `${python} -c "import pathlib;from rs_bpe.bpe import openai;text=pathlib.Path('bench/fixtures/english-1mb.txt').read_text();openai.o200k_base().encode(text)"`,
  });
}

if (availability.token_dagger) {
  commands.push({
    name: "python-ram-token-dagger-encode-1mb",
    command:
      `${python} -c "import importlib.util,pathlib;text=pathlib.Path('bench/fixtures/english-1mb.txt').read_text()\nif importlib.util.find_spec('token_dagger'):\n import token_dagger as td\n enc=td.get_encoding('o200k_base')\nelse:\n import tiktoken,tokendagger as td\n base=tiktoken.get_encoding('o200k_base')\n enc=td.Encoding('o200k_base',pat_str=base._pat_str,mergeable_ranks=base._mergeable_ranks,special_tokens=base._special_tokens)\nenc.encode(text)"`,
  });
}

if (availability.gpt_tokenizer) {
  commands.push({
    name: "js-ram-gpt-tokenizer-encode-1mb",
    command:
      `bun -e "import { encode } from 'gpt-tokenizer'; import { readFileSync } from 'node:fs'; const text = readFileSync('bench/fixtures/english-1mb.txt', 'utf8'); encode(text);"`,
  });
}

const timeFlag = process.platform === "darwin" ? "-l" : "-v";
const rows = [];

for (const item of commands) {
  section(`RSS: ${item.name}`);
  const samples: MemorySample[] = [];
  for (let i = 0; i < runs; i += 1) {
    const result = runShell(`/usr/bin/time ${timeFlag} ${item.command}`, { allowFailure: true });
    const maxRssKb = parseMaxRssKb(result.stderr);
    const sample: MemorySample = {
      run: i + 1,
      exitCode: result.code,
      maxRssKb,
      stdout: result.stdout,
      stderr: result.stderr,
    };
    samples.push(sample);
    const rssText = maxRssKb == null ? "n/a" : `${(maxRssKb / 1024).toFixed(2)} MB`;
    console.log(`run ${i + 1}/${runs}: exit=${result.code} peak_rss=${rssText}`);
  }

  const successful = samples
    .filter((sample) => sample.exitCode === 0 && sample.maxRssKb != null)
    .map((sample) => sample.maxRssKb as number);

  rows.push({
    name: item.name,
    command: item.command,
    runs,
    successfulRuns: successful.length,
    medianRssKb: median(successful),
    meanRssKb:
      successful.length > 0
        ? successful.reduce((acc, value) => acc + value, 0) / successful.length
        : null,
    minRssKb: successful.length > 0 ? Math.min(...successful) : null,
    maxRssKb: successful.length > 0 ? Math.max(...successful) : null,
    samples,
  });
}

const baselineRow = rows.find((row) => row.name === "python-empty-baseline");
const baselineMedianKb = baselineRow?.medianRssKb ?? null;

for (const row of rows) {
  row.deltaOverBaselineKb =
    baselineMedianKb != null && row.medianRssKb != null
      ? row.medianRssKb - baselineMedianKb
      : null;
}

const outputPath = resolvePath("bench", "results", `bench-ram-${Date.now()}.json`);
writeJson(outputPath, {
  tool: "/usr/bin/time",
  generatedAt: new Date().toISOString(),
  platform: process.platform,
  runsPerCommand: runs,
  availability,
  baseline: "python-empty-baseline",
  rows,
  note: "Peak RSS benchmark for o200k_base encode on 1MB fixture. Includes baseline and available competitors.",
});

console.log(`Wrote RAM benchmark record: ${outputPath}`);
process.exit(0);
