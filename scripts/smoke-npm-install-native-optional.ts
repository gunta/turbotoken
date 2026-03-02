#!/usr/bin/env bun
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { commandExists, resolvePath, runCommand, section, writeJson } from "./_lib";

function hostNativePackageName(): string {
  const key = `${process.platform}-${process.arch}`;
  switch (key) {
    case "darwin-arm64":
      return "@turbotoken/native-darwin-arm64";
    case "linux-x64":
      return "@turbotoken/native-linux-x64-gnu";
    case "linux-arm64":
      return "@turbotoken/native-linux-arm64-gnu";
    case "win32-x64":
      return "@turbotoken/native-win32-x64-gnu";
    default:
      throw new Error(`unsupported host for optional native smoke: ${key}`);
  }
}

function tarballPrefixForPackage(name: string): string {
  return name.replace(/^@/, "").replace(/\//g, "-");
}

section("npm package smoke install (optional native package)");

const outputPath = resolvePath("dist", "npm", `smoke-npm-install-native-optional-${Date.now()}.json`);
if (!commandExists("npm")) {
  writeJson(outputPath, { status: "failed", reason: "npm not found" });
  throw new Error("npm is required");
}
if (!commandExists("bun")) {
  writeJson(outputPath, { status: "failed", reason: "bun not found" });
  throw new Error("bun is required");
}

const nativePackageName = hostNativePackageName();
const nativePrefix = tarballPrefixForPackage(nativePackageName);

runCommand("bun", ["run", "scripts/pack-native-packages.ts"], {
  env: { TURBOTOKEN_NATIVE_PACKAGE_TARGETS: "host" },
});

const tarballRoot = resolvePath("dist", "native-packages", "tarballs");
const nativeTarball = readdirSync(tarballRoot)
  .filter((entry) => entry.endsWith(".tgz") && entry.startsWith(nativePrefix))
  .map((entry) => resolvePath("dist", "native-packages", "tarballs", entry))
  .at(-1);

if (!nativeTarball || !existsSync(nativeTarball)) {
  writeJson(outputPath, {
    status: "failed",
    reason: `host optional native tarball not found for ${nativePackageName}`,
    tarballRoot,
  });
  throw new Error(`host optional native tarball not found for ${nativePackageName}`);
}

const pack = runCommand("npm", ["pack", "--silent"], { allowFailure: true });
if (pack.code !== 0) {
  writeJson(outputPath, {
    status: "failed",
    reason: "npm pack failed",
    stdout: pack.stdout,
    stderr: pack.stderr,
  });
  throw new Error(pack.stderr.trim() || pack.stdout.trim() || "npm pack failed");
}

const rootTarballName = pack.stdout
  .trim()
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => line.length > 0)
  .at(-1);
if (!rootTarballName) {
  writeJson(outputPath, {
    status: "failed",
    reason: "npm pack did not output root tarball filename",
    stdout: pack.stdout,
  });
  throw new Error("npm pack did not output root tarball filename");
}

const rootTarballPath = resolvePath(rootTarballName);
if (!existsSync(rootTarballPath)) {
  writeJson(outputPath, {
    status: "failed",
    reason: `missing root tarball: ${rootTarballPath}`,
  });
  throw new Error(`missing root tarball: ${rootTarballPath}`);
}

const tempRoot = mkdtempSync(join(tmpdir(), "turbotoken-npm-native-smoke-"));
const installDir = join(tempRoot, "install");

let checkCode = 1;
let checkStdout = "";
let checkStderr = "";
try {
  mkdirSync(installDir, { recursive: true });
  runCommand("npm", ["init", "-y"], { cwd: installDir });
  runCommand("npm", ["install", "--no-audit", "--no-fund", rootTarballPath, nativeTarball], { cwd: installDir });

  const checkScript = [
    "import { getEncodingAsync } from 'turbotoken';",
    "const enc = await getEncodingAsync('o200k_base');",
    "if (enc.backendKind() !== 'native') {",
    "  throw new Error(`expected native backend with optional package installed, got ${enc.backendKind()}`);",
    "}",
    "const tokens = await enc.encodeAsync('hello optional native package');",
    "const text = await enc.decodeAsync(tokens);",
    "if (text !== 'hello optional native package') {",
    "  throw new Error(`native optional roundtrip mismatch: ${text}`);",
    "}",
    "console.log(JSON.stringify({ backend: enc.backendKind(), tokenCount: tokens.length }));",
  ].join("\n");
  const check = runCommand("bun", ["-e", checkScript], {
    cwd: installDir,
    allowFailure: true,
  });
  checkCode = check.code;
  checkStdout = check.stdout.trim();
  checkStderr = check.stderr.trim();
} finally {
  rmSync(tempRoot, { recursive: true, force: true });
  rmSync(rootTarballPath, { force: true });
}

writeJson(outputPath, {
  status: checkCode === 0 ? "ok" : "failed",
  nativePackageName,
  nativeTarball,
  rootTarballPath,
  checkCode,
  checkStdout,
  checkStderr,
  note: "Installs root package tarball + host optional native tarball and verifies auto backend resolves to native.",
});

if (checkCode !== 0) {
  console.error(`npm optional native smoke install failed: ${outputPath}`);
  process.exit(checkCode);
}

console.log(`npm optional native smoke install passed: ${outputPath}`);
