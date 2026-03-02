#!/usr/bin/env bun
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { resolvePath, section, writeJson } from "./_lib";

type JsonMap = Record<string, unknown>;

interface RelativeMaxGate {
  baseline?: number;
  maxRegressionPct?: number;
}

interface RelativeMinGate {
  baseline?: number;
  maxDropPct?: number;
}

interface CpuRelativeGates {
  startupColdMs?: RelativeMaxGate;
  encode1mbMs?: RelativeMaxGate;
  count1mbMs?: RelativeMaxGate;
  training100kbNativeMs?: RelativeMaxGate;
  peakRssEncode1mbMb?: RelativeMaxGate;
  encode1mbMiBPerSec?: RelativeMinGate;
  count1mbMiBPerSec?: RelativeMinGate;
}

interface GpuRelativeGates {
  maxDeviceAllocatedMiB?: RelativeMaxGate;
  directBpeEncodeMiBPerSec?: RelativeMinGate;
}

interface RelativeGatesConfig {
  enabled?: boolean;
  cpu?: CpuRelativeGates;
  gpu?: GpuRelativeGates;
}

interface ProfileConfig {
  host?: {
    platform?: string;
    arch?: string;
  };
  relative?: RelativeGatesConfig;
}

interface GatesConfig {
  version: number;
  profiles?: Record<string, ProfileConfig>;
}

interface BenchmarkArtifact {
  path: string;
  payload: JsonMap;
}

interface ProfileUpdateRow {
  metric: string;
  oldBaseline: number;
  newBaseline: number;
}

interface ProfileRefreshResult {
  profile: string;
  status: "updated" | "skipped";
  reason?: string;
  artifactPath?: string;
  updates?: ProfileUpdateRow[];
}

function isRecord(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null;
}

function toNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function parseStringArg(argv: string[], key: string): string | null {
  const match = argv.find((arg) => arg.startsWith(`${key}=`));
  if (!match) {
    return null;
  }
  const value = match.slice(`${key}=`.length).trim();
  return value.length > 0 ? value : null;
}

function parseProfiles(argv: string[]): string[] {
  const raw = parseStringArg(argv, "--profile");
  if (!raw) {
    return [];
  }
  return raw
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function normalizeSpeedProfile(raw: string | null): "fast" | "full" | null {
  if (!raw) {
    return null;
  }
  const lowered = raw.trim().toLowerCase();
  if (lowered === "fast" || lowered === "quick") {
    return "fast";
  }
  if (lowered === "full") {
    return "full";
  }
  if (lowered === "any" || lowered === "*") {
    return null;
  }
  throw new Error(`invalid speed profile ${JSON.stringify(raw)} (expected full|fast|any)`);
}

function parseSpeedProfile(argv: string[]): "fast" | "full" | null {
  const raw = parseStringArg(argv, "--speed") ?? (process.env.TURBOTOKEN_CI_ARTIFACT_SPEED ?? "full");
  return normalizeSpeedProfile(raw);
}

function artifactSummarySpeed(payload: JsonMap): "fast" | "full" | null {
  const selection = payload["artifactSelection"];
  if (isRecord(selection)) {
    const raw = selection["speedProfile"];
    if (typeof raw === "string") {
      return normalizeSpeedProfile(raw);
    }
  }
  const legacy = payload["speedProfile"];
  if (typeof legacy === "string") {
    return normalizeSpeedProfile(legacy);
  }
  return null;
}

function profileFromLegacyFilename(name: string): string | null {
  const match = /^ci-benchmark-(all|cpu|gpu)-(.+)-\d+-\d+\.json$/.exec(name);
  if (!match) {
    return null;
  }
  const profile = match[2];
  if (profile === "default") {
    return null;
  }
  return profile;
}

function matchesHost(expected: ProfileConfig["host"] | undefined, payload: JsonMap, allowHostMismatch: boolean): boolean {
  if (allowHostMismatch) {
    return true;
  }
  if (!expected || (!expected.platform && !expected.arch)) {
    return true;
  }
  const host = payload["host"];
  if (!isRecord(host)) {
    return false;
  }
  if (expected.platform && host["platform"] !== expected.platform) {
    return false;
  }
  if (expected.arch && host["arch"] !== expected.arch) {
    return false;
  }
  return true;
}

function isSuccessfulArtifact(payload: JsonMap): boolean {
  const failures = payload["failures"];
  return Array.isArray(failures) && failures.length === 0;
}

function roundBaseline(value: number): number {
  return Math.round(value * 1_000_000) / 1_000_000;
}

function updateCpuBaselines(cpu: CpuRelativeGates, metrics: JsonMap, updates: ProfileUpdateRow[]): void {
  const mapping: Array<{
    gate: RelativeMaxGate | RelativeMinGate | undefined;
    metricName: keyof CpuRelativeGates;
    metricValue: number | null;
  }> = [
    { gate: cpu.startupColdMs, metricName: "startupColdMs", metricValue: toNumber(metrics["startupColdMs"]) },
    { gate: cpu.encode1mbMs, metricName: "encode1mbMs", metricValue: toNumber(metrics["encode1mbMs"]) },
    { gate: cpu.count1mbMs, metricName: "count1mbMs", metricValue: toNumber(metrics["count1mbMs"]) },
    {
      gate: cpu.training100kbNativeMs,
      metricName: "training100kbNativeMs",
      metricValue: toNumber(metrics["training100kbNativeMs"]),
    },
    {
      gate: cpu.peakRssEncode1mbMb,
      metricName: "peakRssEncode1mbMb",
      metricValue: toNumber(metrics["peakRssEncode1mbMb"]),
    },
    {
      gate: cpu.encode1mbMiBPerSec,
      metricName: "encode1mbMiBPerSec",
      metricValue: toNumber(metrics["encode1mbMiBPerSec"]),
    },
    {
      gate: cpu.count1mbMiBPerSec,
      metricName: "count1mbMiBPerSec",
      metricValue: toNumber(metrics["count1mbMiBPerSec"]),
    },
  ];

  for (const row of mapping) {
    if (!row.gate || row.metricValue == null) {
      continue;
    }
    const oldBaseline = toNumber(row.gate["baseline"]);
    if (oldBaseline == null) {
      continue;
    }
    const nextBaseline = roundBaseline(row.metricValue);
    if (nextBaseline === oldBaseline) {
      continue;
    }
    row.gate["baseline"] = nextBaseline;
    updates.push({
      metric: String(row.metricName),
      oldBaseline,
      newBaseline: nextBaseline,
    });
  }
}

function updateGpuBaselines(gpu: GpuRelativeGates, metrics: JsonMap, updates: ProfileUpdateRow[]): void {
  const gpuMetrics = metrics["gpuMemory"];
  if (!isRecord(gpuMetrics)) {
    return;
  }

  const maxDeviceAllocatedMiB = toNumber(gpuMetrics["maxDeviceAllocatedMiB"]);
  const directBpeEncodeMiBPerSec = toNumber(gpuMetrics["bestBpeDirectMiBPerSec"]);

  if (gpu.maxDeviceAllocatedMiB) {
    const oldBaseline = toNumber(gpu.maxDeviceAllocatedMiB.baseline);
    if (oldBaseline != null && maxDeviceAllocatedMiB != null) {
      const nextBaseline = roundBaseline(maxDeviceAllocatedMiB);
      if (nextBaseline !== oldBaseline) {
        gpu.maxDeviceAllocatedMiB.baseline = nextBaseline;
        updates.push({
          metric: "maxDeviceAllocatedMiB",
          oldBaseline,
          newBaseline: nextBaseline,
        });
      }
    }
  }

  if (gpu.directBpeEncodeMiBPerSec) {
    const oldBaseline = toNumber(gpu.directBpeEncodeMiBPerSec.baseline);
    if (oldBaseline != null && directBpeEncodeMiBPerSec != null) {
      const nextBaseline = roundBaseline(directBpeEncodeMiBPerSec);
      if (nextBaseline !== oldBaseline) {
        gpu.directBpeEncodeMiBPerSec.baseline = nextBaseline;
        updates.push({
          metric: "directBpeEncodeMiBPerSec",
          oldBaseline,
          newBaseline: nextBaseline,
        });
      }
    }
  }
}

function selectArtifacts(resultsDir: string): BenchmarkArtifact[] {
  return readdirSync(resultsDir)
    .filter((name) => name.startsWith("ci-benchmark-") && name.endsWith(".json") && !name.endsWith(".meta.json"))
    .sort()
    .reverse()
    .map((name) => {
      const path = join(resultsDir, name);
      try {
        const payload = JSON.parse(readFileSync(path, "utf8")) as JsonMap;
        return { path, payload };
      } catch {
        return null;
      }
    })
    .filter((item): item is BenchmarkArtifact => item !== null);
}

section("Refresh CI gate baselines");

const argv = process.argv.slice(2);
const dryRun = argv.includes("--dry-run");
const allowHostMismatch = argv.includes("--allow-host-mismatch");
const gatesPath = parseStringArg(argv, "--gates") ?? resolvePath("bench", "ci-gates.json");
const resultsDir = parseStringArg(argv, "--results-dir") ?? resolvePath("bench", "results");
const speedProfile = parseSpeedProfile(argv);
const requestedProfiles = parseProfiles(argv);

const gates = JSON.parse(readFileSync(gatesPath, "utf8")) as GatesConfig;
if (!isRecord(gates) || !isRecord(gates.profiles)) {
  throw new Error(`gates config does not define profiles: ${gatesPath}`);
}

const profiles = gates.profiles as Record<string, ProfileConfig>;
const targetProfiles = requestedProfiles.length > 0 ? requestedProfiles : Object.keys(profiles).sort();
if (targetProfiles.length === 0) {
  throw new Error("no profiles selected for baseline refresh");
}

const artifacts = selectArtifacts(resultsDir);
const results: ProfileRefreshResult[] = [];
let updateCount = 0;

for (const profileName of targetProfiles) {
  const profile = profiles[profileName];
  if (!isRecord(profile)) {
    results.push({
      profile: profileName,
      status: "skipped",
      reason: "profile not found in gates config",
    });
    continue;
  }
  if (!isRecord(profile.relative)) {
    results.push({
      profile: profileName,
      status: "skipped",
      reason: "profile has no relative gate config",
    });
    continue;
  }

  let selected: BenchmarkArtifact | null = null;
  for (const artifact of artifacts) {
    const payload = artifact.payload;
    const selectedProfileRaw = payload["selectedProfile"];
    const selectedProfile =
      typeof selectedProfileRaw === "string" && selectedProfileRaw.length > 0
        ? selectedProfileRaw
        : profileFromLegacyFilename(artifact.path.split("/").at(-1) ?? "");
    if (selectedProfile !== profileName) {
      continue;
    }
    if (!isSuccessfulArtifact(payload)) {
      continue;
    }
    if (speedProfile != null) {
      const observedSpeed = artifactSummarySpeed(payload);
      if (observedSpeed !== speedProfile) {
        continue;
      }
    }
    if (!matchesHost(profile.host, payload, allowHostMismatch)) {
      continue;
    }
    selected = artifact;
    break;
  }

  if (!selected) {
    results.push({
      profile: profileName,
      status: "skipped",
      reason: "no matching successful artifact found for profile/host",
    });
    continue;
  }

  const metrics = selected.payload["metrics"];
  if (!isRecord(metrics)) {
    results.push({
      profile: profileName,
      status: "skipped",
      reason: "artifact metrics missing",
      artifactPath: selected.path,
    });
    continue;
  }

  const updates: ProfileUpdateRow[] = [];
  if (isRecord(profile.relative?.cpu)) {
    updateCpuBaselines(profile.relative!.cpu as CpuRelativeGates, metrics, updates);
  }
  if (isRecord(profile.relative?.gpu)) {
    updateGpuBaselines(profile.relative!.gpu as GpuRelativeGates, metrics, updates);
  }

  if (updates.length === 0) {
    results.push({
      profile: profileName,
      status: "skipped",
      reason: "artifact found but no baseline values changed",
      artifactPath: selected.path,
    });
    continue;
  }

  updateCount += updates.length;
  results.push({
    profile: profileName,
    status: "updated",
    artifactPath: selected.path,
    updates,
  });
}

if (!dryRun && updateCount > 0) {
  writeFileSync(gatesPath, `${JSON.stringify(gates, null, 2)}\n`, "utf8");
}

const summaryPath = resolvePath("bench", "results", `ci-gates-refresh-${Date.now()}.json`);
writeJson(summaryPath, {
  generatedAt: new Date().toISOString(),
  speedProfile: speedProfile ?? "any",
  gatesPath,
  resultsDir,
  dryRun,
  allowHostMismatch,
  updatedFields: updateCount,
  results,
});

console.log(`Wrote refresh summary: ${summaryPath}`);
if (!dryRun && updateCount > 0) {
  console.log(`Updated gate baselines in ${gatesPath} (${updateCount} fields).`);
} else if (dryRun) {
  console.log("Dry run only; no gate file changes were written.");
} else {
  console.log("No baseline updates were applied.");
}
