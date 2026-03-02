#!/usr/bin/env bun
import { existsSync, mkdirSync, readdirSync, renameSync } from "node:fs";
import { basename, resolve } from "node:path";
import { resolvePath, runCommand, section, writeJson } from "./_lib";

interface PackRow {
  stageDir: string;
  packageName: string;
  status: "ok" | "failed";
  tarballPath?: string;
  reason?: string;
}

section("Pack optional native npm packages");

runCommand("bun", ["run", "scripts/build-native-packages.ts"], {
  env: process.env.TURBOTOKEN_NATIVE_PACKAGE_TARGETS
    ? { TURBOTOKEN_NATIVE_PACKAGE_TARGETS: process.env.TURBOTOKEN_NATIVE_PACKAGE_TARGETS }
    : undefined,
});

const stagingRoot = resolvePath("dist", "native-packages", "staging");
const tarballRoot = resolvePath("dist", "native-packages", "tarballs");
const resultPath = resolvePath("dist", "native-packages", `pack-native-packages-${Date.now()}.json`);
mkdirSync(tarballRoot, { recursive: true });

const stageDirs = existsSync(stagingRoot)
  ? readdirSync(stagingRoot).map((entry) => resolvePath("dist", "native-packages", "staging", entry))
  : [];

const rows: PackRow[] = [];
let failed = false;

for (const stageDir of stageDirs) {
  const row: PackRow = {
    stageDir,
    packageName: basename(stageDir),
    status: "failed",
  };
  rows.push(row);
  const packed = runCommand("npm", ["pack", "--silent"], { cwd: stageDir, allowFailure: true });
  if (packed.code !== 0) {
    row.status = "failed";
    row.reason = packed.stderr.trim() || packed.stdout.trim() || "npm pack failed";
    failed = true;
    continue;
  }
  const tarballName = packed.stdout
    .trim()
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .at(-1);
  if (!tarballName) {
    row.status = "failed";
    row.reason = "npm pack did not output tarball name";
    failed = true;
    continue;
  }
  const sourceTarball = resolve(stageDir, tarballName);
  const targetTarball = resolvePath(tarballRoot, tarballName);
  renameSync(sourceTarball, targetTarball);
  row.status = "ok";
  row.tarballPath = targetTarball;
}

writeJson(resultPath, {
  generatedAt: new Date().toISOString(),
  status: failed ? "failed" : "ok",
  stagingRoot,
  tarballRoot,
  rows,
  note: "Packs staged optional native packages into tarballs for publish/install testing.",
});

for (const row of rows) {
  const suffix = row.status === "ok" ? row.tarballPath : row.reason;
  console.log(`${row.packageName}: ${row.status}${suffix ? ` (${suffix})` : ""}`);
}
console.log(`Wrote native package pack report: ${resultPath}`);

if (failed) {
  process.exit(1);
}
