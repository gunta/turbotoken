#!/usr/bin/env bun
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { commandExists, ensureDir, resolvePath, runCommand, section, writeJson } from "./_lib";

interface DryRunCommand {
  command: string;
  args: string[];
  cwd?: string;
}

type SupportTier = "ga" | "beta" | "experimental";

interface PackageSpec {
  id: string;
  ecosystem: string;
  packageName: string;
  supportTier: SupportTier;
  wrapperDir: string;
  manifestPath: string;
  readmePath: string;
  publishCommand: string;
  dryRun?: DryRunCommand;
}

interface PackageResult {
  id: string;
  ecosystem: string;
  packageName: string;
  supportTier: SupportTier;
  manifestPath: string;
  readmePath: string;
  wrapperDir: string;
  checks: {
    manifestExists: boolean;
    readmeExists: boolean;
    metadataIssues: string[];
  };
  dryRun?: {
    attempted: boolean;
    status: "passed" | "failed" | "skipped";
    command?: string;
    cwd?: string;
    exitCode?: number;
    reason?: string;
    stdout?: string;
    stderr?: string;
  };
  publishCommand: string;
}

interface ReleaseMatrix {
  packages: PackageSpec[];
}

function parseOptionValues(prefix: string): string[] {
  return process.argv
    .filter((arg) => arg.startsWith(prefix))
    .map((arg) => arg.slice(prefix.length).trim())
    .filter((value) => value.length > 0);
}

function parseTierFilter(): SupportTier | "all" {
  const values = parseOptionValues("--tier=");
  if (values.length === 0) {
    return "all";
  }
  const last = values[values.length - 1];
  if (last === "all" || last === "ga" || last === "beta" || last === "experimental") {
    return last;
  }
  throw new Error(`invalid --tier value: ${last}. expected one of ga,beta,experimental,all`);
}

function parsePackageIdFilter(): Set<string> | undefined {
  const rawValues = parseOptionValues("--package-id=");
  if (rawValues.length === 0) {
    return undefined;
  }
  const packageIds = rawValues
    .flatMap((value) => value.split(","))
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  return packageIds.length > 0 ? new Set(packageIds) : undefined;
}

function hasTomlKey(text: string, key: string): boolean {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^\\s*${escaped}\\s*=\\s*`, "m").test(text);
}

function requireRegex(text: string, pattern: RegExp, issue: string, out: string[]): void {
  if (!pattern.test(text)) {
    out.push(issue);
  }
}

function metadataIssues(spec: PackageSpec, manifestText: string): string[] {
  const issues: string[] = [];
  const eco = spec.ecosystem;

  if (eco === "npm" || eco === "packagist" || eco === "jsr") {
    try {
      const parsed = JSON.parse(manifestText) as Record<string, unknown>;
      for (const key of ["name", "version"]) {
        if (typeof parsed[key] !== "string" || (parsed[key] as string).trim().length === 0) {
          issues.push(`missing JSON field: ${key}`);
        }
      }
      if (eco === "npm" || eco === "packagist") {
        for (const key of ["description", "license"]) {
          if (typeof parsed[key] !== "string" || (parsed[key] as string).trim().length === 0) {
            issues.push(`missing JSON field: ${key}`);
          }
        }
      }
      if (eco === "npm" && parsed.repository === undefined) {
        issues.push("missing JSON field: repository");
      }
      if (eco === "jsr" && parsed.exports === undefined) {
        issues.push("missing JSON field: exports");
      }
    } catch {
      issues.push("manifest is not valid JSON");
    }
    return issues;
  }

  if (eco === "pypi") {
    requireRegex(manifestText, /^\[project\]/m, "missing [project] table", issues);
    requireRegex(manifestText, /^name\s*=\s*".+"/m, "missing project.name", issues);
    requireRegex(manifestText, /^version\s*=\s*".+"/m, "missing project.version", issues);
    requireRegex(manifestText, /^license\s*=/m, "missing project.license", issues);
    return issues;
  }

  if (eco === "crates") {
    requireRegex(manifestText, /^\[package\]/m, "missing [package] table", issues);
    for (const key of ["name", "version", "license"]) {
      if (!hasTomlKey(manifestText, key)) {
        issues.push(`missing Cargo key: ${key}`);
      }
    }
    return issues;
  }

  if (eco === "go") {
    requireRegex(manifestText, /^module\s+\S+/m, "missing go module declaration", issues);
    return issues;
  }

  if (eco === "rubygems") {
    requireRegex(manifestText, /s\.name\s*=/, "missing gemspec s.name", issues);
    requireRegex(manifestText, /s\.version\s*=/, "missing gemspec s.version", issues);
    requireRegex(manifestText, /s\.license\s*=/, "missing gemspec s.license", issues);
    return issues;
  }

  if (eco === "maven") {
    if (spec.manifestPath.endsWith(".xml")) {
      requireRegex(manifestText, /<groupId>[^<]+<\/groupId>/, "missing pom groupId", issues);
      requireRegex(manifestText, /<artifactId>[^<]+<\/artifactId>/, "missing pom artifactId", issues);
      requireRegex(manifestText, /<version>[^<]+<\/version>/, "missing pom version", issues);
      requireRegex(manifestText, /<licenses>/, "missing pom licenses", issues);
    } else if (spec.manifestPath.endsWith(".sbt")) {
      requireRegex(manifestText, /^\s*name\s*:?=\s*".+"/m, "missing sbt name", issues);
      requireRegex(manifestText, /^\s*version\s*:?=\s*".+"/m, "missing sbt version", issues);
      requireRegex(manifestText, /^\s*organization\s*:?=\s*".+"/m, "missing sbt organization", issues);
    } else {
      requireRegex(manifestText, /group\s*=\s*["'][^"']+["']/, "missing Gradle group", issues);
      requireRegex(manifestText, /version\s*=\s*["'][^"']+["']/, "missing Gradle version", issues);
    }
    return issues;
  }

  if (eco === "nuget") {
    requireRegex(manifestText, /<PackageId>[^<]+<\/PackageId>/, "missing csproj PackageId", issues);
    requireRegex(manifestText, /<Version>[^<]+<\/Version>/, "missing csproj Version", issues);
    requireRegex(manifestText, /<PackageLicenseExpression>[^<]+<\/PackageLicenseExpression>/, "missing csproj PackageLicenseExpression", issues);
    return issues;
  }

  if (eco === "hex") {
    requireRegex(manifestText, /app:\s*:[a-z_]+/, "missing mix app field", issues);
    if (!/version:\s*"[^"]+"/.test(manifestText) && !/version:\s*@\w+/.test(manifestText)) {
      issues.push("missing mix version field");
    }
    requireRegex(manifestText, /description:\s*"[^"]+"/, "missing mix description field", issues);
    return issues;
  }

  if (eco === "gleam") {
    for (const key of ["name", "version", "licences"]) {
      if (!hasTomlKey(manifestText, key)) {
        issues.push(`missing gleam.toml key: ${key}`);
      }
    }
    return issues;
  }

  if (eco === "clojars") {
    requireRegex(manifestText, /^\(defproject\s+\S+\s+"[^"]+"/m, "missing defproject declaration", issues);
    requireRegex(manifestText, /:license\s+\{/, "missing :license block", issues);
    return issues;
  }

  if (eco === "julia") {
    for (const key of ["name", "version"]) {
      if (!hasTomlKey(manifestText, key)) {
        issues.push(`missing Project.toml key: ${key}`);
      }
    }
    return issues;
  }

  if (eco === "cran") {
    requireRegex(manifestText, /^Package:\s+\S+/m, "missing DESCRIPTION Package", issues);
    requireRegex(manifestText, /^Version:\s+\S+/m, "missing DESCRIPTION Version", issues);
    requireRegex(manifestText, /^License:\s+.+/m, "missing DESCRIPTION License", issues);
    return issues;
  }

  if (eco === "swiftpm") {
    requireRegex(manifestText, /let\s+package\s*=\s*Package\(/, "missing Swift Package declaration", issues);
    return issues;
  }

  if (eco === "luarocks") {
    requireRegex(manifestText, /^package\s*=\s*".+"/m, "missing rockspec package", issues);
    requireRegex(manifestText, /^version\s*=\s*".+"/m, "missing rockspec version", issues);
    requireRegex(manifestText, /license\s*=\s*".+"/m, "missing rockspec license", issues);
    return issues;
  }

  if (eco === "pub") {
    requireRegex(manifestText, /^name:\s+\S+/m, "missing pubspec name", issues);
    requireRegex(manifestText, /^version:\s+\S+/m, "missing pubspec version", issues);
    requireRegex(manifestText, /^description:\s+.+/m, "missing pubspec description", issues);
    return issues;
  }

  return issues;
}

function compactOutput(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.length <= 2500) {
    return trimmed;
  }
  return `${trimmed.slice(0, 2500)}\n...[truncated]`;
}

function markdownReport(
  results: PackageResult[],
  dryRun: boolean,
  tierFilter: SupportTier | "all",
  packageIdFilter: Set<string> | undefined,
  failOnSkipped: boolean,
): string {
  const lines: string[] = [];
  lines.push("# Release Readiness");
  lines.push("");
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push(`Mode: ${dryRun ? "check + dry-run" : "check-only"}`);
  lines.push(`Tier filter: ${tierFilter}`);
  lines.push(`Package filter: ${packageIdFilter ? [...packageIdFilter].sort().join(", ") : "all"}`);
  if (dryRun) {
    lines.push(`Fail on skipped dry-runs: ${failOnSkipped ? "enabled" : "disabled"}`);
  }
  lines.push("");
  lines.push("| Package | Ecosystem | Tier | Manifest | README | Metadata | Dry-run |");
  lines.push("|---|---|---|---|---|---|---|");

  for (const row of results) {
    const manifest = row.checks.manifestExists ? "OK" : "MISSING";
    const readme = row.checks.readmeExists ? "OK" : "MISSING";
    const meta = row.checks.metadataIssues.length === 0 ? "OK" : `${row.checks.metadataIssues.length} issue(s)`;
    const dry = row.dryRun ? row.dryRun.status.toUpperCase() : "N/A";
    lines.push(`| ${row.packageName} | ${row.ecosystem} | ${row.supportTier} | ${manifest} | ${readme} | ${meta} | ${dry} |`);
  }

  lines.push("");
  lines.push("## Publish Commands");
  lines.push("");
  for (const row of results) {
    lines.push(`- \`${row.packageName}\` (${row.ecosystem}): \`${row.publishCommand}\``);
  }

  const issueRows = results.filter((row) => row.checks.metadataIssues.length > 0);
  if (issueRows.length > 0) {
    lines.push("");
    lines.push("## Metadata Issues");
    lines.push("");
    for (const row of issueRows) {
      lines.push(`- \`${row.packageName}\`: ${row.checks.metadataIssues.join("; ")}`);
    }
  }

  const failedRows = results.filter((row) => row.dryRun?.status === "failed");
  if (failedRows.length > 0) {
    lines.push("");
    lines.push("## Dry-run Failures");
    lines.push("");
    for (const row of failedRows) {
      lines.push(`- \`${row.packageName}\`: ${row.dryRun?.reason ?? "failed"}`);
    }
  }

  const skippedRows = results.filter((row) => row.dryRun?.status === "skipped");
  if (skippedRows.length > 0) {
    lines.push("");
    lines.push("## Dry-run Skips");
    lines.push("");
    for (const row of skippedRows) {
      lines.push(`- \`${row.packageName}\`: ${row.dryRun?.reason ?? "skipped"}`);
    }
  }

  return `${lines.join("\n")}\n`;
}

const runDry = process.argv.includes("--dry-run");
const failOnSkipped = process.argv.includes("--fail-on-skipped");
const tierFilter = parseTierFilter();
const packageIdFilter = parsePackageIdFilter();
const matrixPath = resolvePath("wrappers", "release-matrix.json");
const matrix = JSON.parse(readFileSync(matrixPath, "utf8")) as ReleaseMatrix;
if (!Array.isArray(matrix.packages) || matrix.packages.length === 0) {
  throw new Error(`release matrix is empty: ${matrixPath}`);
}

const invalidTierPackages = matrix.packages
  .filter((spec) => spec.supportTier !== "ga" && spec.supportTier !== "beta" && spec.supportTier !== "experimental")
  .map((spec) => spec.id);
if (invalidTierPackages.length > 0) {
  throw new Error(`invalid supportTier in release matrix for package(s): ${invalidTierPackages.join(", ")}`);
}

const unknownPackageIds = [...(packageIdFilter ?? [])].filter(
  (id) => !matrix.packages.some((spec) => spec.id === id),
);
if (unknownPackageIds.length > 0) {
  throw new Error(`unknown --package-id value(s): ${unknownPackageIds.join(", ")}`);
}

const selectedPackages = matrix.packages.filter((spec) => {
  if (tierFilter !== "all" && spec.supportTier !== tierFilter) {
    return false;
  }
  if (packageIdFilter && !packageIdFilter.has(spec.id)) {
    return false;
  }
  return true;
});
if (selectedPackages.length === 0) {
  throw new Error(
    `no packages selected (tier=${tierFilter}, package-id=${packageIdFilter ? [...packageIdFilter].join(",") : "all"})`,
  );
}

section("Release readiness check");
const results: PackageResult[] = [];
let failures = 0;
console.log(`Scope: ${selectedPackages.length}/${matrix.packages.length} package(s)`);
console.log(`Tier filter: ${tierFilter}`);
if (packageIdFilter) {
  console.log(`Package filter: ${[...packageIdFilter].sort().join(", ")}`);
}
if (runDry) {
  console.log(`Fail on skipped dry-runs: ${failOnSkipped ? "enabled" : "disabled"}`);
}

for (const spec of selectedPackages) {
  const manifestPath = resolvePath(spec.manifestPath);
  const readmePath = resolvePath(spec.readmePath);
  const manifestExists = existsSync(manifestPath);
  const readmeExists = existsSync(readmePath);
  const issues: string[] = [];

  if (!manifestExists) {
    issues.push("manifest file missing");
  }
  if (!readmeExists) {
    issues.push("README file missing");
  }

  let manifestText = "";
  if (manifestExists) {
    manifestText = readFileSync(manifestPath, "utf8");
    issues.push(...metadataIssues(spec, manifestText));
  }

  const row: PackageResult = {
    id: spec.id,
    ecosystem: spec.ecosystem,
    packageName: spec.packageName,
    supportTier: spec.supportTier,
    manifestPath: spec.manifestPath,
    readmePath: spec.readmePath,
    wrapperDir: spec.wrapperDir,
    checks: {
      manifestExists,
      readmeExists,
      metadataIssues: issues,
    },
    publishCommand: spec.publishCommand,
  };

  if (issues.length > 0) {
    failures += 1;
  }

  if (runDry) {
    if (!spec.dryRun) {
      row.dryRun = {
        attempted: false,
        status: "skipped",
        reason: "dry-run command not configured",
      };
      if (failOnSkipped) {
        failures += 1;
      }
    } else {
      const dry = spec.dryRun;
      const cwd = resolvePath(dry.cwd ?? spec.wrapperDir);
      const joined = [dry.command, ...dry.args].join(" ");
      if (!commandExists(dry.command)) {
        row.dryRun = {
          attempted: false,
          status: "skipped",
          command: joined,
          cwd,
          reason: `${dry.command} not found`,
        };
        if (failOnSkipped) {
          failures += 1;
        }
      } else {
        const exec = runCommand(dry.command, dry.args, {
          cwd,
          allowFailure: true,
          timeoutMs: 15 * 60 * 1000,
        });
        row.dryRun = {
          attempted: true,
          status: exec.code === 0 ? "passed" : "failed",
          command: joined,
          cwd,
          exitCode: exec.code,
          reason: exec.code === 0 ? undefined : (exec.stderr.trim() || exec.stdout.trim() || "command failed"),
          stdout: compactOutput(exec.stdout),
          stderr: compactOutput(exec.stderr),
        };
        if (exec.code !== 0) {
          failures += 1;
        }
      }
    }
  }

  results.push(row);
}

const outputDir = resolvePath("dist", "release");
ensureDir(outputDir);
const stamp = Date.now();
const jsonPath = resolvePath("dist", "release", `release-readiness-${stamp}.json`);
const markdownPath = resolvePath("dist", "release", `release-readiness-${stamp}.md`);
writeJson(jsonPath, {
  generatedAt: new Date().toISOString(),
  mode: runDry ? "check+dry-run" : "check-only",
  scope: {
    tierFilter,
    packageIds: packageIdFilter ? [...packageIdFilter].sort() : [],
    failOnSkipped,
  },
  matrixPath,
  total: selectedPackages.length,
  matrixTotal: matrix.packages.length,
  failures,
  results,
});

const markdown = markdownReport(results, runDry, tierFilter, packageIdFilter, failOnSkipped);
ensureDir(dirname(markdownPath));
writeFileSync(markdownPath, markdown, "utf8");

console.log(`Release readiness JSON: ${jsonPath}`);
console.log(`Release readiness Markdown: ${markdownPath}`);
console.log(`Packages checked: ${results.length}`);
console.log(`Failures: ${failures}`);

process.exit(failures === 0 ? 0 : 1);
