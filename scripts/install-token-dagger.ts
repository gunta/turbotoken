#!/usr/bin/env bun
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  rmSync,
  statSync,
  unlinkSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pythonExecutable, runCommand, runShell, section } from "./_lib";

const python = process.env.TURBOTOKEN_BENCH_PYTHON?.trim() || pythonExecutable();
const keepTemp = process.env.TOKEN_DAGGER_KEEP_TEMP === "1";
const skipUninstall = process.env.TOKEN_DAGGER_SKIP_UNINSTALL === "1";

function prependEnvVar(
  env: Record<string, string>,
  key: string,
  value: string,
  separator = ":",
): void {
  const current = process.env[key]?.trim();
  env[key] = current && current.length > 0 ? `${value}${separator}${current}` : value;
}

function findPcre2Prefix(): string | null {
  const override = process.env.PCRE2_PREFIX?.trim();
  if (override && override.length > 0) {
    return override;
  }

  const brew = runCommand("brew", ["--prefix", "pcre2"], { allowFailure: true });
  if (brew.code === 0 && brew.stdout.trim().length > 0) {
    return brew.stdout.trim();
  }

  const pkgConfig = runShell("pkg-config --variable=prefix libpcre2-8", { allowFailure: true });
  if (pkgConfig.code === 0 && pkgConfig.stdout.trim().length > 0) {
    return pkgConfig.stdout.trim();
  }

  return null;
}

function extractSdist(pythonExe: string, archivePath: string, outputDir: string): void {
  const extractor = [
    "import pathlib,sys,tarfile,zipfile",
    "archive=pathlib.Path(sys.argv[1])",
    "out=pathlib.Path(sys.argv[2])",
    "out.mkdir(parents=True, exist_ok=True)",
    "if archive.suffix == '.zip':",
    "  with zipfile.ZipFile(archive) as zf:",
    "    zf.extractall(out)",
    "else:",
    "  with tarfile.open(archive) as tf:",
    "    tf.extractall(out)",
  ].join("\n");
  runCommand(pythonExe, ["-c", extractor, archivePath, outputDir]);
}

function findSourceRoot(extractDir: string): string {
  const entries = readdirSync(extractDir)
    .map((name) => resolve(extractDir, name))
    .filter((path) => statSync(path).isDirectory());

  for (const path of entries) {
    if (existsSync(resolve(path, "setup.py")) || existsSync(resolve(path, "pyproject.toml"))) {
      return path;
    }
  }

  throw new Error(`Could not find extracted source root under ${extractDir}`);
}

function stripBundledObjects(sourceRoot: string): string[] {
  const nativeDir = resolve(sourceRoot, "src", "tiktoken");
  if (!existsSync(nativeDir)) {
    return [];
  }

  const removed: string[] = [];
  for (const file of readdirSync(nativeDir)) {
    if (file.endsWith(".o") || file.endsWith(".a")) {
      const target = resolve(nativeDir, file);
      unlinkSync(target);
      removed.push(target);
    }
  }

  return removed;
}

section("Install token-dagger from cleaned sdist");
console.log(`python: ${python}`);

const tempRoot = mkdtempSync(join(tmpdir(), "turbotoken-token-dagger-"));
const downloadDir = resolve(tempRoot, "download");
const extractDir = resolve(tempRoot, "extract");
mkdirSync(downloadDir, { recursive: true });
mkdirSync(extractDir, { recursive: true });
console.log(`temp root: ${tempRoot}`);

if (!skipUninstall) {
  runCommand(
    python,
    ["-m", "pip", "uninstall", "-y", "token-dagger", "tokendagger", "token_dagger"],
    { allowFailure: true },
  );
}

const requestedSpec = process.env.TOKEN_DAGGER_SPEC?.trim();
const packageCandidates = requestedSpec ? [requestedSpec] : ["token-dagger", "tokendagger"];
const downloadErrors: string[] = [];
let packageSpec = "";
for (const candidate of packageCandidates) {
  const attempt = runCommand(
    python,
    ["-m", "pip", "download", "--no-binary=:all:", "--no-deps", candidate, "-d", downloadDir],
    { allowFailure: true },
  );
  if (attempt.code === 0) {
    packageSpec = candidate;
    break;
  }
  const details = [attempt.stdout.trim(), attempt.stderr.trim()].filter((v) => v.length > 0).join("\n");
  downloadErrors.push(`[${candidate}] ${details}`);
}
if (packageSpec.length === 0) {
  throw new Error(`Unable to download token-dagger source package.\n${downloadErrors.join("\n\n")}`);
}
console.log(`package: ${packageSpec}`);

const archives = readdirSync(downloadDir)
  .filter((name) => name.endsWith(".tar.gz") || name.endsWith(".zip"))
  .map((name) => resolve(downloadDir, name))
  .sort();
if (archives.length === 0) {
  throw new Error(`No source archive downloaded to ${downloadDir}`);
}

const archivePath = archives[archives.length - 1];
console.log(`archive: ${archivePath}`);

extractSdist(python, archivePath, extractDir);
const sourceRoot = findSourceRoot(extractDir);
console.log(`source root: ${sourceRoot}`);

const removed = stripBundledObjects(sourceRoot);
if (removed.length > 0) {
  section("Removed stale bundled native artifacts");
  for (const file of removed) {
    console.log(file);
  }
}

const installEnv: Record<string, string> = {};
const pcre2Prefix = findPcre2Prefix();
if (pcre2Prefix) {
  const includeDir = resolve(pcre2Prefix, "include");
  const libDir = resolve(pcre2Prefix, "lib");
  prependEnvVar(installEnv, "CPATH", includeDir);
  prependEnvVar(installEnv, "LIBRARY_PATH", libDir);
  prependEnvVar(installEnv, "CPPFLAGS", `-I${includeDir}`, " ");
  prependEnvVar(installEnv, "LDFLAGS", `-L${libDir}`, " ");
  console.log(`pcre2 prefix: ${pcre2Prefix}`);
} else {
  console.warn(
    "pcre2 prefix was not auto-detected; continuing with current environment variables.",
  );
}

runCommand(
  python,
  ["-m", "pip", "install", "--no-cache-dir", "--force-reinstall", sourceRoot],
  { env: installEnv },
);

const smoke = [
  "import importlib.util",
  "if importlib.util.find_spec('token_dagger'):",
  "  import token_dagger as td",
  "  enc=td.get_encoding('o200k_base')",
  "  s='token-dagger smoke test'",
  "  assert enc.decode(enc.encode(s))==s",
  "else:",
  "  import tokendagger as td",
  "  if importlib.util.find_spec('tiktoken') is None:",
  "    print('tokendagger import OK (tiktoken not installed; skipping encode/decode smoke).')",
  "    raise SystemExit(0)",
  "  import tiktoken",
  "  base=tiktoken.get_encoding('o200k_base')",
  "  enc=td.Encoding('o200k_base',pat_str=base._pat_str,mergeable_ranks=base._mergeable_ranks,special_tokens=base._special_tokens)",
  "  s='token-dagger smoke test'",
  "  assert enc.decode(enc.encode(s))==s",
  "print('token-dagger build/install smoke test: OK')",
].join("\n");
runCommand(python, ["-c", smoke], { env: installEnv });

if (!keepTemp) {
  rmSync(tempRoot, { recursive: true, force: true });
}
