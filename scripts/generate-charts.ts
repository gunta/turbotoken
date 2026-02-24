#!/usr/bin/env bun
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { ensureDir, resolvePath, section } from "./_lib";

interface ChartRow {
  file: string;
  command: string;
  meanSeconds: number | null;
}

function extractRows(path: string): ChartRow[] {
  const raw = readFileSync(path, "utf8");
  const json = JSON.parse(raw) as Record<string, unknown>;
  const file = path.split("/").at(-1) ?? path;

  if (Array.isArray(json.results) && json.tool === "manual") {
    return json.results
      .map((item) => {
        if (!item || typeof item !== "object") {
          return null;
        }
        const maybe = item as Record<string, unknown>;
        return {
          file,
          command: String(maybe.commandName ?? "unknown"),
          meanSeconds: typeof maybe.meanSeconds === "number" ? maybe.meanSeconds : null,
        };
      })
      .filter((item): item is ChartRow => item !== null);
  }

  if (Array.isArray(json.results)) {
    return json.results
      .map((item) => {
        if (!item || typeof item !== "object") {
          return null;
        }
        const maybe = item as Record<string, unknown>;
        return {
          file,
          command: String(maybe.command ?? maybe.commandName ?? "unknown"),
          meanSeconds: typeof maybe.mean === "number" ? maybe.mean : null,
        };
      })
      .filter((item): item is ChartRow => item !== null);
  }

  return [];
}

section("Generating benchmark summary");

const resultsDir = resolvePath("bench", "results");
const chartDir = resolvePath("bench", "charts");
const summaryPath = resolve(chartDir, "summary.md");

ensureDir(chartDir);

const rows: ChartRow[] = [];
for (const entry of readdirSync(resultsDir)) {
  if (!entry.endsWith(".json")) {
    continue;
  }
  const fullPath = resolve(resultsDir, entry);
  try {
    rows.push(...extractRows(fullPath));
  } catch {
    // Ignore malformed JSON and keep chart generation resilient.
  }
}

rows.sort((a, b) => {
  if (a.command === b.command) {
    return a.file.localeCompare(b.file);
  }
  return a.command.localeCompare(b.command);
});

const lines = [
  "# Benchmark Summary",
  "",
  `Generated: ${new Date().toISOString()}`,
  "",
  "| Source JSON | Command | Mean (ms) |",
  "|-------------|---------|-----------|",
];

for (const row of rows) {
  const meanMs = row.meanSeconds === null ? "n/a" : (row.meanSeconds * 1000).toFixed(3);
  lines.push(`| ${row.file} | ${row.command} | ${meanMs} |`);
}

if (rows.length === 0) {
  lines.push("| n/a | n/a | n/a |", "", "No benchmark rows found in `bench/results/`.");
}

writeFileSync(summaryPath, `${lines.join("\n")}\n`, "utf8");
console.log(`Wrote chart summary: ${summaryPath}`);
