#!/usr/bin/env bun
import { runBench, type BenchCommand } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable, runShell } from "./_lib";

ensureFixtures();
const python = pythonExecutable();
const iterations = 256;
const modeArg = process.argv.find((arg) => arg.startsWith("--mode="));
const mode = modeArg ? modeArg.slice("--mode=".length) : "baseline";

if (mode !== "baseline" && mode !== "sme-auto") {
  console.error(`unsupported mode: ${mode}; expected --mode=baseline or --mode=sme-auto`);
  process.exit(2);
}

const smeAutoEnvPrefix = mode === "sme-auto" ? "TURBOTOKEN_EXPERIMENTAL_SME_AUTO=1 " : "";
const fixtures = [
  {
    id: "english-1mb",
    path: "bench/fixtures/english-1mb.txt",
    profile: "mixed-ascii",
  },
  {
    id: "unicode-1mb",
    path: "bench/fixtures/unicode-1mb.txt",
    profile: "non-ascii-heavy",
  },
];

function benchCommand(name: string, fixturePath: string, symbol: string): BenchCommand {
  return {
    name,
    command:
      `${smeAutoEnvPrefix}${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('${fixturePath}').read_bytes();expected=sum((b>>7) for b in data);iters=${iterations};count=0\nfor _ in range(iters):\n count=int(getattr(lib,'${symbol}')(data,len(data)))\nassert count==expected"`,
  };
}

const commands: BenchCommand[] = [];

for (const fixture of fixtures) {
  commands.push(
    benchCommand(
      `turbotoken-native-count-non-ascii-${fixture.id}-auto`,
      fixture.path,
      "turbotoken_count_non_ascii_utf8",
    ),
    benchCommand(
      `turbotoken-native-count-non-ascii-${fixture.id}-scalar`,
      fixture.path,
      "turbotoken_count_non_ascii_utf8_scalar",
    ),
    benchCommand(
      `turbotoken-native-count-non-ascii-${fixture.id}-neon`,
      fixture.path,
      "turbotoken_count_non_ascii_utf8_neon",
    ),
  );
}

const dotprodProbe = runShell(
  `${smeAutoEnvPrefix}${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();sys.exit(0 if int(lib.turbotoken_count_non_ascii_utf8_dotprod(data,len(data))) >= 0 else 1)"`,
  { allowFailure: true },
);

if (dotprodProbe.code === 0) {
  for (const fixture of fixtures) {
    commands.push(
      benchCommand(
        `turbotoken-native-count-non-ascii-${fixture.id}-dotprod`,
        fixture.path,
        "turbotoken_count_non_ascii_utf8_dotprod",
      ),
    );
  }
} else {
  console.warn("DotProd kernel is unavailable for this build/target; benchmark will skip explicit dotprod command.");
}

const smeProbe = runShell(
  `${smeAutoEnvPrefix}${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();sys.exit(0 if int(lib.turbotoken_count_non_ascii_utf8_sme(data,len(data))) >= 0 else 1)"`,
  { allowFailure: true },
);

if (smeProbe.code === 0) {
  for (const fixture of fixtures) {
    commands.push(
      benchCommand(
        `turbotoken-native-count-non-ascii-${fixture.id}-sme`,
        fixture.path,
        "turbotoken_count_non_ascii_utf8_sme",
      ),
    );
  }
} else {
  console.warn("SME kernel is unavailable for this build/target; benchmark will skip explicit sme command.");
}

process.exit(
  runBench({
    name: mode === "sme-auto" ? "bench-native-pretokenizer-sme-auto" : "bench-native-pretokenizer",
    commands,
    metadata: {
      mode,
      smeAutoEnv: mode === "sme-auto" ? "TURBOTOKEN_EXPERIMENTAL_SME_AUTO=1" : "",
      fixtures,
      iterationsPerSample: iterations,
      includesDotProd: dotprodProbe.code === 0,
      includesSme: smeProbe.code === 0,
      note: "native C ABI non-ascii byte counting with auto-dispatch vs scalar/neon/dotprod/sme kernels across mixed-ascii and non-ascii-heavy fixtures; run baseline and sme-auto modes separately",
    },
  }),
);
