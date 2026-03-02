#!/usr/bin/env bun
import { copyFileSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { resolvePath, runCommand, section, writeJson, zigExecutable } from "./_lib";

interface NativePackageSpec {
  id: string;
  name: string;
  target: string;
  libName: string;
  os: string[];
  cpu: string[];
}

interface NativePackageRow {
  id: string;
  name: string;
  target: string;
  libName: string;
  status: "ok" | "failed" | "skipped";
  reason?: string;
  sourcePath?: string;
  stageDir?: string;
  bytes?: number;
}

const PACKAGE_SPECS: NativePackageSpec[] = [
  {
    id: "darwin-arm64",
    name: "@turbotoken/native-darwin-arm64",
    target: "aarch64-macos",
    libName: "libturbotoken.dylib",
    os: ["darwin"],
    cpu: ["arm64"],
  },
  {
    id: "linux-x64-gnu",
    name: "@turbotoken/native-linux-x64-gnu",
    target: "x86_64-linux-gnu",
    libName: "libturbotoken.so",
    os: ["linux"],
    cpu: ["x64"],
  },
  {
    id: "linux-x64-musl",
    name: "@turbotoken/native-linux-x64-musl",
    target: "x86_64-linux-musl",
    libName: "libturbotoken.so",
    os: ["linux"],
    cpu: ["x64"],
  },
  {
    id: "linux-arm64-gnu",
    name: "@turbotoken/native-linux-arm64-gnu",
    target: "aarch64-linux-gnu",
    libName: "libturbotoken.so",
    os: ["linux"],
    cpu: ["arm64"],
  },
  {
    id: "linux-arm64-musl",
    name: "@turbotoken/native-linux-arm64-musl",
    target: "aarch64-linux-musl",
    libName: "libturbotoken.so",
    os: ["linux"],
    cpu: ["arm64"],
  },
  {
    id: "win32-x64-gnu",
    name: "@turbotoken/native-win32-x64-gnu",
    target: "x86_64-windows-gnu",
    libName: "turbotoken.dll",
    os: ["win32"],
    cpu: ["x64"],
  },
];

function rootVersion(): string {
  const pkgJson = JSON.parse(readFileSync(resolvePath("package.json"), "utf8")) as { version?: string };
  const version = pkgJson.version?.trim();
  if (!version) {
    throw new Error("package.json is missing version");
  }
  return version;
}

function hostTargetId(): string {
  const key = `${process.platform}-${process.arch}`;
  switch (key) {
    case "darwin-arm64":
      return "darwin-arm64";
    case "linux-x64":
      return "linux-x64-gnu";
    case "linux-arm64":
      return "linux-arm64-gnu";
    case "win32-x64":
      return "win32-x64-gnu";
    default:
      return "";
  }
}

function selectedSpecs(): NativePackageSpec[] {
  const raw = process.env.TURBOTOKEN_NATIVE_PACKAGE_TARGETS?.trim();
  if (!raw) {
    return PACKAGE_SPECS;
  }
  const values = raw.split(",").map((item) => item.trim()).filter((item) => item.length > 0);
  if (values.length === 1 && values[0].toLowerCase() === "host") {
    const host = hostTargetId();
    if (!host) {
      throw new Error(`unsupported host for native package target selection: ${process.platform}-${process.arch}`);
    }
    return PACKAGE_SPECS.filter((spec) => spec.id === host);
  }
  const set = new Set(values.map((value) => value.toLowerCase()));
  const picked = PACKAGE_SPECS.filter((spec) => set.has(spec.id.toLowerCase()) || set.has(spec.name.toLowerCase()));
  if (picked.length === 0) {
    throw new Error(`no native package specs matched TURBOTOKEN_NATIVE_PACKAGE_TARGETS=${raw}`);
  }
  return picked;
}

function nativeSourceCandidates(libName: string): string[] {
  if (libName.endsWith(".dll")) {
    return [
      resolvePath("zig-out", "bin", libName),
      resolvePath("zig-out", "bin", "libturbotoken.dll"),
      resolvePath("zig-out", "lib", libName),
    ];
  }
  return [
    resolvePath("zig-out", "lib", libName),
    resolvePath("zig-out", "bin", libName),
  ];
}

function writePackageFiles(stageDir: string, spec: NativePackageSpec, version: string): void {
  const packageJson = {
    name: spec.name,
    version,
    description: `Native Zig library for turbotoken (${spec.id})`,
    license: "MIT",
    os: spec.os,
    cpu: spec.cpu,
    files: [spec.libName, "README.md", "LICENSE"],
    sideEffects: false,
  };
  writeFileSync(resolve(stageDir, "package.json"), `${JSON.stringify(packageJson, null, 2)}\n`, "utf8");
  const readme = [
    `# ${spec.name}`,
    "",
    `Prebuilt native Zig shared library for \`turbotoken\` on \`${spec.id}\`.`,
    "",
    "This package is consumed as an optional dependency by `turbotoken`.",
    "",
    `- target: \`${spec.target}\``,
    `- library: \`${spec.libName}\``,
    "",
  ].join("\n");
  writeFileSync(resolve(stageDir, "README.md"), readme, "utf8");
  copyFileSync(resolvePath("LICENSE"), resolve(stageDir, "LICENSE"));
}

section("Build optional native npm packages");

const version = rootVersion();
const stagingRoot = resolvePath("dist", "native-packages", "staging");
const resultPath = resolvePath("dist", "native-packages", `build-native-packages-${Date.now()}.json`);
rmSync(stagingRoot, { recursive: true, force: true });
mkdirSync(stagingRoot, { recursive: true });

const zig = zigExecutable();
const rows: NativePackageRow[] = [];
let failed = false;

for (const spec of selectedSpecs()) {
  const row: NativePackageRow = {
    id: spec.id,
    name: spec.name,
    target: spec.target,
    libName: spec.libName,
    status: "failed",
  };
  rows.push(row);

  try {
    runCommand(zig, ["build", `-Dtarget=${spec.target}`, "-Doptimize=ReleaseFast"]);
    const sourcePath = nativeSourceCandidates(spec.libName).find((candidate) => {
      try {
        return statSync(candidate).size > 0;
      } catch {
        return false;
      }
    });
    if (!sourcePath) {
      row.status = "failed";
      row.reason = `native library not found for ${spec.target}`;
      failed = true;
      continue;
    }

    const stageDir = resolvePath(stagingRoot, spec.id);
    mkdirSync(stageDir, { recursive: true });
    writePackageFiles(stageDir, spec, version);
    copyFileSync(sourcePath, resolve(stageDir, spec.libName));
    row.status = "ok";
    row.sourcePath = sourcePath;
    row.stageDir = stageDir;
    row.bytes = statSync(resolve(stageDir, spec.libName)).size;
  } catch (error) {
    row.status = "failed";
    row.reason = String(error);
    failed = true;
  }
}

writeJson(resultPath, {
  generatedAt: new Date().toISOString(),
  status: failed ? "failed" : "ok",
  version,
  stagingRoot,
  rows,
  note: "Builds and stages per-platform native npm packages for optionalDependencies.",
});

for (const row of rows) {
  const suffix = row.status === "ok" ? `${row.bytes} bytes` : row.reason ?? "failed";
  console.log(`${row.name}: ${row.status} (${suffix})`);
}
console.log(`Wrote native package build report: ${resultPath}`);

if (failed) {
  process.exit(1);
}
