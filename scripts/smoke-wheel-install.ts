#!/usr/bin/env bun
import { existsSync, mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { commandExists, resolvePath, runCommand, section, writeJson } from "./_lib";

function hostWheelTag(): string | null {
  if (process.platform === "darwin" && process.arch === "arm64") {
    return "macosx_11_0_arm64";
  }
  if (process.platform === "linux" && process.arch === "x64") {
    return "manylinux_2_17_x86_64";
  }
  if (process.platform === "linux" && process.arch === "arm64") {
    return "manylinux_2_17_aarch64";
  }
  if (process.platform === "win32" && process.arch === "x64") {
    return "win_amd64";
  }
  return null;
}

section("Wheel install smoke");
const outputPath = resolvePath("dist", "wheels", `smoke-wheel-install-${Date.now()}.json`);
const wheelDir = resolvePath("dist", "wheels");
const allWheels = readdirSync(wheelDir)
  .filter((name) => name.endsWith(".whl"))
  .sort();

if (allWheels.length === 0) {
  writeJson(outputPath, {
    status: "failed",
    reason: "no wheel files found under dist/wheels",
  });
  console.error("No wheels found in dist/wheels.");
  process.exit(1);
}

const tag = hostWheelTag();
if (!tag) {
  writeJson(outputPath, {
    status: "failed",
    reason: `unsupported host platform for wheel smoke: ${process.platform}/${process.arch}`,
  });
  console.error(`Unsupported host platform for wheel smoke: ${process.platform}/${process.arch}`);
  process.exit(1);
}

const candidate = allWheels.find((name) => name.includes(tag));
if (!candidate) {
  writeJson(outputPath, {
    status: "failed",
    reason: `no wheel matching host tag ${tag}`,
    allWheels,
  });
  console.error(`No wheel matching host tag ${tag}.`);
  process.exit(1);
}

if (!commandExists("python3")) {
  writeJson(outputPath, {
    status: "failed",
    reason: "python3 not found",
    wheel: candidate,
  });
  console.error("python3 is required for wheel smoke install.");
  process.exit(1);
}

const wheelPath = resolvePath("dist", "wheels", candidate);
const tempRoot = mkdtempSync(join(tmpdir(), "turbotoken-wheel-smoke-"));
const venvDir = join(tempRoot, ".venv");
const venvPython = process.platform === "win32" ? join(venvDir, "Scripts", "python.exe") : join(venvDir, "bin", "python");

let checkStdout = "";
let checkStderr = "";
let checkCode = 1;

try {
  runCommand("python3", ["-m", "venv", venvDir]);
  runCommand(venvPython, ["-m", "pip", "install", "-U", "pip"]);
  runCommand(venvPython, ["-m", "pip", "install", "--force-reinstall", wheelPath]);

  const checkScript = [
    "import json",
    "from turbotoken import get_encoding",
    "from turbotoken._native import get_native_bridge",
    "enc = get_encoding('o200k_base')",
    "tokens = enc.encode('hello')",
    "decoded = enc.decode(tokens)",
    "bridge = get_native_bridge()",
    "payload = {",
    "  'tokens': tokens,",
    "  'decoded': decoded,",
    "  'nativeAvailable': bool(bridge.available),",
    "  'nativeError': str(bridge.error) if bridge.error else None,",
    "}",
    "print(json.dumps(payload))",
    "if decoded != 'hello':",
    "  raise SystemExit(2)",
    "if not bridge.available:",
    "  raise SystemExit(3)",
  ].join("\n");

  const check = runCommand(venvPython, ["-c", checkScript], { allowFailure: true });
  checkStdout = check.stdout.trim();
  checkStderr = check.stderr.trim();
  checkCode = check.code;
} finally {
  rmSync(tempRoot, { force: true, recursive: true });
}

let parsed: Record<string, unknown> | null = null;
if (checkStdout.length > 0) {
  try {
    parsed = JSON.parse(checkStdout) as Record<string, unknown>;
  } catch {
    parsed = null;
  }
}

writeJson(outputPath, {
  status: checkCode === 0 ? "ok" : "failed",
  wheelPath,
  hostTag: tag,
  checkCode,
  checkStdout,
  checkStderr,
  parsed,
  note: "Installs the host wheel into an isolated venv and validates import + hello roundtrip + native bridge availability.",
});

if (checkCode !== 0) {
  console.error(`Wheel install smoke failed: ${outputPath}`);
  process.exit(checkCode);
}

console.log(`Wheel install smoke passed: ${outputPath}`);
