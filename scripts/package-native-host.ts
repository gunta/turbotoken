#!/usr/bin/env bun
import { copyFileSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname } from "node:path";
import { resolvePath, section, writeJson, zigExecutable, runCommand } from "./_lib";

interface NativeHostReport {
  status: "ok" | "failed";
  reason: string | null;
  platform: string;
  arch: string;
  sourcePath: string | null;
  destinationPath: string | null;
  note: string;
}

function nativeFileNames(ext: string): string[] {
  if (ext === "dll") {
    return ["turbotoken.dll", "libturbotoken.dll"];
  }
  return [`libturbotoken.${ext}`];
}

function nativeExtForPlatform(platform: NodeJS.Platform): string | null {
  switch (platform) {
    case "darwin":
      return "dylib";
    case "linux":
      return "so";
    case "win32":
      return "dll";
    default:
      return null;
  }
}

section("Package host native Zig library");

const resultPath = resolvePath("dist", "npm", `package-native-host-${Date.now()}.json`);
const ext = nativeExtForPlatform(process.platform);
const platformArch = `${process.platform}-${process.arch}`;
const report: NativeHostReport = {
  status: "failed",
  reason: null,
  platform: process.platform,
  arch: process.arch,
  sourcePath: null,
  destinationPath: null,
  note: "Builds host libturbotoken shared library and stages it under wrappers/js/native/host/<platform-arch>/ for npm packaging.",
};

if (!ext) {
  report.reason = `unsupported platform for host native packaging: ${process.platform}`;
  writeJson(resultPath, report);
  console.error(report.reason);
  process.exit(1);
}

const zig = zigExecutable();
runCommand(zig, ["build", "-Doptimize=ReleaseFast"]);

const candidates = nativeFileNames(ext).flatMap((name) => [
  resolvePath("zig-out", "lib", name),
  resolvePath("zig-out", "bin", name),
]);
const sourcePath = candidates.find((candidate) => existsSync(candidate));
if (!sourcePath) {
  report.reason = `no native shared library found after build (${candidates.join(", ")})`;
  writeJson(resultPath, report);
  console.error(report.reason);
  process.exit(1);
}

const destinationPath = resolvePath("js", "native", "host", platformArch, nativeFileNames(ext)[0]);
rmSync(resolvePath("js", "native", "host"), { recursive: true, force: true });
mkdirSync(dirname(destinationPath), { recursive: true });
copyFileSync(sourcePath, destinationPath);

report.status = "ok";
report.sourcePath = sourcePath;
report.destinationPath = destinationPath;
writeJson(resultPath, report);
console.log(`Host native library staged: ${destinationPath}`);
console.log(`Wrote native host package report: ${resultPath}`);
