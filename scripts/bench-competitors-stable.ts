#!/usr/bin/env bun
import { readdirSync, readFileSync } from "node:fs";
import { basename } from "node:path";
import { acquireBenchmarkLock, dateTag, resolvePath, runCommand, section, writeJson } from "./_lib";

acquireBenchmarkLock({ label: "bench-competitors-stable" });

type HyperfineResult = {
  command: string;
  mean: number;
};

type HyperfineJson = {
  results: HyperfineResult[];
};

type Group = "encode" | "decode" | "count";

interface PassFiles {
  pass: number;
  encode: string;
  decode: string;
  count: string;
}

function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  if (sorted.length === 0) {
    return Number.NaN;
  }
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

function latestResult(prefix: string): string {
  const dir = resolvePath("bench/results");
  const files = readdirSync(dir)
    .filter((name) => name.startsWith(prefix) && name.endsWith(".json") && !name.endsWith(".meta.json"))
    .sort()
    .reverse();
  if (files.length === 0) {
    throw new Error(`No result files found for prefix: ${prefix}`);
  }
  return resolvePath("bench/results", files[0]);
}

function loadHyperfine(path: string): HyperfineJson {
  return JSON.parse(readFileSync(path, "utf8")) as HyperfineJson;
}

function collectMedians(passFiles: PassFiles[]) {
  const byGroup = {
    encode: new Map<string, number[]>(),
    decode: new Map<string, number[]>(),
    count: new Map<string, number[]>(),
  };

  for (const pass of passFiles) {
    const groups: Array<[Group, string]> = [
      ["encode", pass.encode],
      ["decode", pass.decode],
      ["count", pass.count],
    ];
    for (const [group, file] of groups) {
      const json = loadHyperfine(file);
      for (const row of json.results) {
        const bucket = byGroup[group].get(row.command) ?? [];
        bucket.push(row.mean * 1000);
        byGroup[group].set(row.command, bucket);
      }
    }
  }

  const out = {
    encode: [] as Array<{ command: string; median_ms: number; samples_ms: number[] }>,
    decode: [] as Array<{ command: string; median_ms: number; samples_ms: number[] }>,
    count: [] as Array<{ command: string; median_ms: number; samples_ms: number[] }>,
  };

  for (const [command, samples] of byGroup.encode.entries()) {
    out.encode.push({ command, median_ms: median(samples), samples_ms: samples });
  }
  for (const [command, samples] of byGroup.decode.entries()) {
    out.decode.push({ command, median_ms: median(samples), samples_ms: samples });
  }
  for (const [command, samples] of byGroup.count.entries()) {
    out.count.push({ command, median_ms: median(samples), samples_ms: samples });
  }

  out.encode.sort((a, b) => a.command.localeCompare(b.command));
  out.decode.sort((a, b) => a.command.localeCompare(b.command));
  out.count.sort((a, b) => a.command.localeCompare(b.command));
  return out;
}

function commandMedian(
  rows: Array<{ command: string; median_ms: number }>,
  command: string,
): number | null {
  const row = rows.find((item) => item.command === command);
  return row ? row.median_ms : null;
}

function summarizeHeadToHead(
  medians: ReturnType<typeof collectMedians>,
): Array<{
  group: Group;
  scenario: string;
  turbotoken_ms: number;
  rs_bpe_ms: number;
  ratio: number;
  winner: "turbotoken" | "rs-bpe";
  input_bytes: number | null;
  turbotoken_mib_per_s: number | null;
  rs_bpe_mib_per_s: number | null;
}> {
  const rows: Array<{
    group: Group;
    scenario: string;
    turbotoken_ms: number;
    rs_bpe_ms: number;
    ratio: number;
    winner: "turbotoken" | "rs-bpe";
    input_bytes: number | null;
    turbotoken_mib_per_s: number | null;
    rs_bpe_mib_per_s: number | null;
  }> = [];

  const scenarios: Array<{
    group: Group;
    scenario: string;
    turbo: string;
    rs: string;
    input_bytes: number | null;
  }> = [
    {
      group: "encode",
      scenario: "1kb",
      turbo: "python-encode-1kb-turbotoken",
      rs: "python-encode-1kb-rs-bpe",
      input_bytes: 1_024,
    },
    {
      group: "encode",
      scenario: "10kb",
      turbo: "python-encode-10kb-turbotoken",
      rs: "python-encode-10kb-rs-bpe",
      input_bytes: 10_240,
    },
    {
      group: "encode",
      scenario: "100kb",
      turbo: "python-encode-100kb-turbotoken",
      rs: "python-encode-100kb-rs-bpe",
      input_bytes: 102_400,
    },
    {
      group: "encode",
      scenario: "1mb",
      turbo: "python-encode-1mb-turbotoken",
      rs: "python-encode-1mb-rs-bpe",
      input_bytes: 1_048_576,
    },
    {
      group: "decode",
      scenario: "1k-tok",
      turbo: "python-decode-1000-tok-turbotoken",
      rs: "python-decode-1000-tok-rs-bpe",
      input_bytes: null,
    },
    {
      group: "decode",
      scenario: "10k-tok",
      turbo: "python-decode-10000-tok-turbotoken",
      rs: "python-decode-10000-tok-rs-bpe",
      input_bytes: null,
    },
    {
      group: "decode",
      scenario: "128k-tok",
      turbo: "python-decode-128000-tok-turbotoken",
      rs: "python-decode-128000-tok-rs-bpe",
      input_bytes: null,
    },
    {
      group: "count",
      scenario: "1kb",
      turbo: "python-count-1kb-turbotoken",
      rs: "python-count-1kb-rs-bpe",
      input_bytes: 1_024,
    },
    {
      group: "count",
      scenario: "100kb",
      turbo: "python-count-100kb-turbotoken",
      rs: "python-count-100kb-rs-bpe",
      input_bytes: 102_400,
    },
    {
      group: "count",
      scenario: "1mb",
      turbo: "python-count-1mb-turbotoken",
      rs: "python-count-1mb-rs-bpe",
      input_bytes: 1_048_576,
    },
  ];

  for (const scenario of scenarios) {
    const groupRows = medians[scenario.group];
    const turbo = commandMedian(groupRows, scenario.turbo);
    const rs = commandMedian(groupRows, scenario.rs);
    if (turbo == null || rs == null) {
      continue;
    }
    const winner: "turbotoken" | "rs-bpe" = turbo <= rs ? "turbotoken" : "rs-bpe";
    const mib = scenario.input_bytes == null ? null : scenario.input_bytes / (1024 * 1024);
    const turboMibPerS = mib == null ? null : mib / (turbo / 1000);
    const rsMibPerS = mib == null ? null : mib / (rs / 1000);
    rows.push({
      group: scenario.group,
      scenario: scenario.scenario,
      turbotoken_ms: turbo,
      rs_bpe_ms: rs,
      ratio: rs / turbo,
      winner,
      input_bytes: scenario.input_bytes,
      turbotoken_mib_per_s: turboMibPerS,
      rs_bpe_mib_per_s: rsMibPerS,
    });
  }
  return rows;
}

const passesRaw = process.env.TURBOTOKEN_BENCH_STABLE_PASSES?.trim();
const passes = passesRaw ? Math.max(1, Number.parseInt(passesRaw, 10) || 3) : 3;

section(`Stable competitors benchmark (${passes} passes)`);

const passFiles: PassFiles[] = [];
for (let pass = 1; pass <= passes; pass += 1) {
  section(`Stable pass ${pass}/${passes}`);
  runCommand("bun", ["run", "scripts/bench-competitors.ts"]);
  passFiles.push({
    pass,
    encode: latestResult("bench-competitors-python-encode-"),
    decode: latestResult("bench-competitors-python-decode-"),
    count: latestResult("bench-competitors-python-count-"),
  });
}

const medians = collectMedians(passFiles);
const headToHead = summarizeHeadToHead(medians);

const outputPath = resolvePath("bench/results", `bench-competitors-stable-${dateTag()}.json`);
writeJson(outputPath, {
  type: "bench-competitors-stable",
  passes,
  pass_files: passFiles.map((row) => ({
    pass: row.pass,
    encode: basename(row.encode),
    decode: basename(row.decode),
    count: basename(row.count),
  })),
  medians,
  head_to_head_vs_rs_bpe: headToHead,
});

console.log(`Wrote stable competitors summary: ${outputPath}`);
for (const row of headToHead) {
  const ratioText = `${row.ratio.toFixed(3)}x`;
  const throughputText =
    row.turbotoken_mib_per_s == null || row.rs_bpe_mib_per_s == null
      ? ""
      : ` turbo=${row.turbotoken_mib_per_s.toFixed(2)}MiB/s rs=${row.rs_bpe_mib_per_s.toFixed(2)}MiB/s`;
  console.log(
    `${row.group} ${row.scenario}: turbotoken=${row.turbotoken_ms.toFixed(3)}ms rs-bpe=${row.rs_bpe_ms.toFixed(3)}ms winner=${row.winner} (${ratioText})${throughputText}`,
  );
}
