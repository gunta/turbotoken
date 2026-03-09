#!/usr/bin/env bun
import { commandExists, repoRoot, runCommand, section } from "./_lib";

type Target = "linux" | "windows" | "macos-intel" | "all";
type BenchmarkSpeed = "fast" | "full";

interface Options {
  target: Target;
  benchmarkSpeed: BenchmarkSpeed;
  runCpuGates: boolean;
  runReleaseCheck: boolean;
  push: boolean;
  wait: boolean;
  ref: string | null;
  remote: string;
  workflow: string;
  dryRun: boolean;
}

interface WorkflowRunSummary {
  databaseId: number;
  status: string;
  workflowName: string;
  headBranch: string;
  headSha: string;
  url: string;
  createdAt: string;
}

function parseBooleanFlag(raw: string, flag: string): boolean {
  const lowered = raw.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(lowered)) {
    return true;
  }
  if (["0", "false", "no", "off"].includes(lowered)) {
    return false;
  }
  throw new Error(`invalid value for ${flag}: ${JSON.stringify(raw)} (expected true|false)`);
}

function parseOption(name: string): string | null {
  const prefix = `${name}=`;
  const match = process.argv.slice(2).find((arg) => arg.startsWith(prefix));
  if (!match) {
    return null;
  }
  const value = match.slice(prefix.length).trim();
  return value.length > 0 ? value : null;
}

function hasFlag(name: string): boolean {
  return process.argv.slice(2).includes(name);
}

function parseTarget(raw: string | null): Target {
  const value = raw ?? "linux";
  if (value === "linux" || value === "windows" || value === "macos-intel" || value === "all") {
    return value;
  }
  throw new Error(`invalid --target value: ${JSON.stringify(value)} (expected linux|windows|macos-intel|all)`);
}

function parseBenchmarkSpeed(raw: string | null): BenchmarkSpeed {
  const value = raw ?? "fast";
  if (value === "fast" || value === "full") {
    return value;
  }
  throw new Error(`invalid --benchmark-speed value: ${JSON.stringify(value)} (expected fast|full)`);
}

function currentBranchName(): string {
  const branch = runCommand("git", ["branch", "--show-current"], { cwd: repoRoot }).stdout.trim();
  if (branch.length === 0) {
    throw new Error("unable to determine current git branch");
  }
  return branch;
}

function resolveRef(options: Options): string {
  if (options.ref) {
    return options.ref;
  }
  return currentBranchName();
}

function resolveHeadSha(ref: string): string {
  const sha = runCommand("git", ["rev-parse", ref], { cwd: repoRoot }).stdout.trim();
  if (sha.length === 0) {
    throw new Error(`unable to resolve head sha for ref ${JSON.stringify(ref)}`);
  }
  return sha;
}

function branchFilterForRunList(ref: string): string | null {
  if (ref.startsWith("refs/heads/")) {
    const branch = ref.slice("refs/heads/".length).trim();
    return branch.length > 0 ? branch : null;
  }
  if (ref.startsWith("refs/")) {
    return null;
  }
  return ref;
}

function ensureGhReady(): void {
  if (!commandExists("gh")) {
    throw new Error("gh CLI is required but was not found in PATH");
  }
  const auth = runCommand("gh", ["auth", "status"], {
    cwd: repoRoot,
    allowFailure: true,
  });
  if (auth.code !== 0) {
    throw new Error("gh CLI is not authenticated. Run `gh auth login` first.");
  }
}

function maybePushRef(options: Options, ref: string): void {
  if (!options.push) {
    return;
  }

  if (ref.includes("/") || ref.startsWith("refs/")) {
    section(`Push ref ${ref}`);
    runCommand("git", ["push", options.remote, ref], { cwd: repoRoot });
    return;
  }

  section(`Push branch ${ref}`);
  const upstream = runCommand("git", ["rev-parse", "--abbrev-ref", `${ref}@{upstream}`], {
    cwd: repoRoot,
    allowFailure: true,
  });
  if (upstream.code === 0) {
    runCommand("git", ["push", options.remote, ref], { cwd: repoRoot });
    return;
  }
  runCommand("git", ["push", "-u", options.remote, ref], { cwd: repoRoot });
}

function workflowDispatchArgs(options: Options, ref: string): string[] {
  return [
    "workflow",
    "run",
    options.workflow,
    "--ref",
    ref,
    "-f",
    `target=${options.target}`,
    "-f",
    `benchmark_speed=${options.benchmarkSpeed}`,
    "-f",
    `run_cpu_gates=${options.runCpuGates ? "true" : "false"}`,
    "-f",
    `run_release_check=${options.runReleaseCheck ? "true" : "false"}`,
  ];
}

async function findDispatchedRun(
  options: Options,
  branchFilter: string,
  expectedHeadSha: string,
): Promise<WorkflowRunSummary> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const runList = runCommand(
      "gh",
      [
        "run",
        "list",
        "--workflow",
        options.workflow,
        "--branch",
        branchFilter,
        "--limit",
        "10",
        "--json",
        "databaseId,status,workflowName,headBranch,headSha,url,createdAt",
      ],
      { cwd: repoRoot },
    );

    const parsed = JSON.parse(runList.stdout) as WorkflowRunSummary[];
    const match = parsed.find((run) => run.headSha === expectedHeadSha);
    if (match) {
      return match;
    }

    await Bun.sleep(2000);
  }

  throw new Error(
    `workflow dispatched for ${expectedHeadSha}, but no matching run was returned by \`gh run list\` after waiting`,
  );
}

function printUsage(): void {
  console.log(`Usage: bun run scripts/trigger-x86-ondemand.ts [options]

Options:
  --target=linux|windows|macos-intel|all
  --benchmark-speed=fast|full
  --run-cpu-gates=true|false
  --run-release-check=true|false
  --ref=<branch-or-ref>
  --remote=<remote-name>              default: origin
  --workflow=<workflow-file>          default: x86-ondemand.yml
  --push                             push ref before dispatch
  --wait                             watch the newly queued run
  --dry-run                          print commands without executing
  --help`);
}

if (hasFlag("--help")) {
  printUsage();
  process.exit(0);
}

const options: Options = {
  target: parseTarget(parseOption("--target")),
  benchmarkSpeed: parseBenchmarkSpeed(parseOption("--benchmark-speed")),
  runCpuGates: parseBooleanFlag(parseOption("--run-cpu-gates") ?? "true", "--run-cpu-gates"),
  runReleaseCheck: parseBooleanFlag(parseOption("--run-release-check") ?? "false", "--run-release-check"),
  push: hasFlag("--push"),
  wait: hasFlag("--wait"),
  ref: parseOption("--ref"),
  remote: parseOption("--remote") ?? "origin",
  workflow: parseOption("--workflow") ?? "x86-ondemand.yml",
  dryRun: hasFlag("--dry-run"),
};

const ref = resolveRef(options);
const expectedHeadSha = resolveHeadSha(ref);
const dispatchArgs = workflowDispatchArgs(options, ref);

section("X86 on-demand trigger");
console.log(
  JSON.stringify(
    {
      workflow: options.workflow,
      ref,
      expectedHeadSha,
      target: options.target,
      benchmarkSpeed: options.benchmarkSpeed,
      runCpuGates: options.runCpuGates,
      runReleaseCheck: options.runReleaseCheck,
      push: options.push,
      wait: options.wait,
      remote: options.remote,
      dryRun: options.dryRun,
    },
    null,
    2,
  ),
);

if (options.dryRun) {
  if (options.push) {
    console.log(`DRY RUN push: git push ${options.remote} ${ref}`);
  }
  console.log(`DRY RUN dispatch: gh ${dispatchArgs.join(" ")}`);
  if (options.wait) {
    console.log(`DRY RUN watch: match workflow run with headSha ${expectedHeadSha} and then gh run watch <databaseId>`);
  }
  process.exit(0);
}

ensureGhReady();
maybePushRef(options, ref);

section("Dispatch workflow");
runCommand("gh", dispatchArgs, { cwd: repoRoot });

if (!options.wait) {
  console.log("Workflow dispatched.");
  process.exit(0);
}

section("Watch matching run");
const branchFilter = branchFilterForRunList(ref);
if (!branchFilter) {
  console.log(`Workflow dispatched for ref ${ref}. Automatic watch is only supported for branch refs.`);
  process.exit(0);
}

const latest = await findDispatchedRun(options, branchFilter, expectedHeadSha);

console.log(`Watching ${latest.workflowName} run ${latest.databaseId}: ${latest.url}`);
runCommand("gh", ["run", "watch", String(latest.databaseId)], { cwd: repoRoot });
