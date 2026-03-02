#!/usr/bin/env bun
import { rmSync } from "node:fs";
import { dirname } from "node:path";
import { commandExists, ensureDir, ensurePythonDevEnvironment, resolvePath, runCommand, section, writeJson } from "./_lib";

interface StepResult {
  name: string;
  command: string;
  cwd: string;
  exitCode: number;
  durationMs: number;
  stdout: string;
  stderr: string;
}

interface SmokeResult {
  status: "ok" | "failed";
  packageId: string;
  generatedAt: string;
  steps: StepResult[];
  reason?: string;
}

function optionValue(prefix: string): string | undefined {
  const value = process.argv
    .filter((arg) => arg.startsWith(prefix))
    .map((arg) => arg.slice(prefix.length).trim())
    .filter((arg) => arg.length > 0)
    .at(-1);
  return value;
}

function compactOutput(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.length <= 4000) {
    return trimmed;
  }
  return `${trimmed.slice(0, 4000)}\n...[truncated]`;
}

const packageId = optionValue("--package-id=");
if (!packageId) {
  throw new Error("missing --package-id=<id>");
}

section(`GA wrapper smoke (${packageId})`);
const outputPath = resolvePath("dist", "release", `ga-wrapper-smoke-${packageId}-${Date.now()}.json`);
const steps: StepResult[] = [];

function envWithLibraryPath(extra: Record<string, string> = {}): Record<string, string> {
  const libDir = resolvePath("zig-out", "lib");
  const ld = process.env.LD_LIBRARY_PATH;
  return {
    LD_LIBRARY_PATH: ld && ld.length > 0 ? `${libDir}:${ld}` : libDir,
    ...extra,
  };
}

function runStep(
  name: string,
  command: string,
  args: string[],
  options: {
    cwd?: string;
    env?: Record<string, string>;
    stdin?: string;
  } = {},
): void {
  if (!commandExists(command)) {
    throw new Error(`required command not found for step '${name}': ${command}`);
  }
  const cwd = options.cwd ?? resolvePath();
  const started = Date.now();
  const exec = runCommand(command, args, {
    cwd,
    env: options.env,
    stdin: options.stdin,
    allowFailure: true,
    timeoutMs: 20 * 60 * 1000,
  });
  const step: StepResult = {
    name,
    command: [command, ...args].join(" "),
    cwd,
    exitCode: exec.code,
    durationMs: Date.now() - started,
    stdout: compactOutput(exec.stdout),
    stderr: compactOutput(exec.stderr),
  };
  steps.push(step);
  if (exec.code !== 0) {
    throw new Error(`step failed: ${name} (${step.command})`);
  }
}

const repoRoot = resolvePath();

try {
  switch (packageId) {
    case "npm-turbotoken": {
      runStep("npm-install-smoke", "bun", ["run", "smoke:npm-install"], {
        cwd: repoRoot,
      });
      break;
    }
    case "npm-react-native": {
      const rnDir = resolvePath("wrappers", "react-native");
      runStep("react-native-install", "npm", ["install", "--no-audit", "--no-fund", "--package-lock=false"], {
        cwd: rnDir,
      });
      runStep("react-native-typecheck", "npm", ["run", "typescript"], {
        cwd: rnDir,
      });
      break;
    }
    case "pypi-python": {
      const python = ensurePythonDevEnvironment();
      runStep(
        "python-roundtrip",
        python,
        [
          "-c",
          [
            "from turbotoken import get_encoding",
            "text='hello ga smoke'",
            "enc=get_encoding('o200k_base')",
            "tokens=enc.encode(text)",
            "decoded=enc.decode(tokens)",
            "assert decoded==text",
            "print(len(tokens))",
          ].join("; "),
        ],
        {
          cwd: repoRoot,
          env: {
            TURBOTOKEN_CACHE_DIR: resolvePath(".cache", "turbotoken"),
          },
        },
      );
      break;
    }
    case "crates-rust": {
      const rustDir = resolvePath("wrappers", "rust");
      runStep(
        "rust-roundtrip-test",
        "cargo",
        ["test", "--test", "encode_test", "test_decode_round_trip", "--", "--nocapture"],
        {
          cwd: rustDir,
          env: envWithLibraryPath({
            TURBOTOKEN_NATIVE_LIB: resolvePath("zig-out", "lib"),
            TURBOTOKEN_CACHE_DIR: resolvePath(".cache", "turbotoken"),
          }),
        },
      );
      break;
    }
    case "golang-go": {
      const goDir = resolvePath("wrappers", "go");
      runStep(
        "go-roundtrip-test",
        "go",
        ["test", "./...", "-run", "TestEncodeDecodeRoundTrip", "-count=1"],
        {
          cwd: goDir,
          env: envWithLibraryPath({
            CGO_ENABLED: "1",
            CGO_CFLAGS: `-I${resolvePath("include")}`,
            CGO_LDFLAGS: `-L${resolvePath("zig-out", "lib")} -lturbotoken`,
            TURBOTOKEN_CACHE_DIR: resolvePath(".cache", "turbotoken"),
          }),
        },
      );
      break;
    }
    case "jsr-deno": {
      const libName = process.platform === "darwin" ? "libturbotoken.dylib" : "libturbotoken.so";
      runStep(
        "deno-roundtrip",
        "deno",
        ["run", "-A", "-"],
        {
          cwd: repoRoot,
          env: envWithLibraryPath({
            TURBOTOKEN_NATIVE_LIB: resolvePath("zig-out", "lib", libName),
            XDG_CACHE_HOME: resolvePath(".cache"),
          }),
          stdin: [
            "import { getEncoding } from './wrappers/deno/mod.ts';",
            "const text = 'hello ga smoke';",
            "const enc = await getEncoding('o200k_base');",
            "const tokens = enc.encode(text);",
            "const decoded = enc.decode(tokens);",
            "if (decoded !== text) throw new Error(`roundtrip mismatch: ${decoded}`);",
            "console.log(tokens.length);",
          ].join("\n"),
        },
      );
      break;
    }
    default:
      throw new Error(`unsupported GA package id for smoke: ${packageId}`);
  }

  const result: SmokeResult = {
    status: "ok",
    packageId,
    generatedAt: new Date().toISOString(),
    steps,
  };
  ensureDir(dirname(outputPath));
  writeJson(outputPath, result);
  console.log(`GA wrapper smoke passed: ${outputPath}`);
} catch (error) {
  const result: SmokeResult = {
    status: "failed",
    packageId,
    generatedAt: new Date().toISOString(),
    steps,
    reason: error instanceof Error ? error.message : String(error),
  };
  ensureDir(dirname(outputPath));
  writeJson(outputPath, result);
  console.error(`GA wrapper smoke failed: ${outputPath}`);
  if (packageId === "npm-react-native") {
    rmSync(resolvePath("wrappers", "react-native", "node_modules"), { recursive: true, force: true });
  }
  process.exit(1);
}

if (packageId === "npm-react-native") {
  rmSync(resolvePath("wrappers", "react-native", "node_modules"), { recursive: true, force: true });
}
