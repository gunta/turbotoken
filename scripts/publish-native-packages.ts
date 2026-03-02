#!/usr/bin/env bun
import { existsSync, readdirSync } from "node:fs";
import { resolvePath, runCommand, section, writeJson } from "./_lib";

interface PublishRow {
  tarballPath: string;
  status: "ok" | "failed";
  reason?: string;
}

function parseTag(): string {
  const raw = process.env.TURBOTOKEN_NATIVE_PUBLISH_TAG?.trim();
  if (!raw) {
    return "dev";
  }
  return raw;
}

function dryRun(): boolean {
  const raw = (process.env.TURBOTOKEN_NATIVE_PUBLISH_DRY_RUN ?? "").trim().toLowerCase();
  return raw === "1" || raw === "true" || raw === "yes" || raw === "on";
}

section("Publish optional native npm packages");

runCommand("bun", ["run", "scripts/pack-native-packages.ts"], {
  env: process.env.TURBOTOKEN_NATIVE_PACKAGE_TARGETS
    ? { TURBOTOKEN_NATIVE_PACKAGE_TARGETS: process.env.TURBOTOKEN_NATIVE_PACKAGE_TARGETS }
    : undefined,
});

const tarballRoot = resolvePath("dist", "native-packages", "tarballs");
const resultPath = resolvePath("dist", "native-packages", `publish-native-packages-${Date.now()}.json`);
const tag = parseTag();
const useDryRun = dryRun();

const tarballs = existsSync(tarballRoot)
  ? readdirSync(tarballRoot)
    .filter((entry) => entry.endsWith(".tgz"))
    .map((entry) => resolvePath(tarballRoot, entry))
  : [];

if (tarballs.length === 0) {
  writeJson(resultPath, {
    generatedAt: new Date().toISOString(),
    status: "failed",
    reason: `no tarballs found in ${tarballRoot}`,
  });
  throw new Error(`no tarballs found in ${tarballRoot}`);
}

const rows: PublishRow[] = [];
let failed = false;
for (const tarballPath of tarballs) {
  const args = ["publish", tarballPath, "--tag", tag, "--access", "public"];
  if (useDryRun) {
    args.push("--dry-run");
  }
  const result = runCommand("npm", args, { allowFailure: true });
  if (result.code !== 0) {
    rows.push({
      tarballPath,
      status: "failed",
      reason: result.stderr.trim() || result.stdout.trim() || "npm publish failed",
    });
    failed = true;
    continue;
  }
  rows.push({
    tarballPath,
    status: "ok",
  });
}

writeJson(resultPath, {
  generatedAt: new Date().toISOString(),
  status: failed ? "failed" : "ok",
  tag,
  dryRun: useDryRun,
  tarballRoot,
  rows,
  note: "Publishes optional native package tarballs to npm.",
});

for (const row of rows) {
  console.log(`${row.tarballPath}: ${row.status}${row.reason ? ` (${row.reason})` : ""}`);
}
console.log(`Wrote native package publish report: ${resultPath}`);

if (failed) {
  process.exit(1);
}
