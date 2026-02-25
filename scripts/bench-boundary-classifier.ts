#!/usr/bin/env bun
import { runBench, type BenchCommand } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable, runShell } from "./_lib";

ensureFixtures();
const python = pythonExecutable();
const iterations = 512;

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
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('${fixturePath}').read_bytes();expected=0\nif len(data)>1:\n prev=(0 if data[0]==32 else (1 if ((65<=data[0]<=90) or (97<=data[0]<=122)) else (2 if (48<=data[0]<=57) else (3 if (33<=data[0]<=126) else 4))))\n for b in data[1:]:\n  cur=(0 if b==32 else (1 if ((65<=b<=90) or (97<=b<=122)) else (2 if (48<=b<=57) else (3 if (33<=b<=126) else 4))))\n  expected+=1 if cur!=prev else 0\n  prev=cur\niters=${iterations};count=0\nfor _ in range(iters):\n count=int(getattr(lib,'${symbol}')(data,len(data)))\nassert count==expected"`,
  };
}

const commands: BenchCommand[] = [];
for (const fixture of fixtures) {
  commands.push(
    benchCommand(
      `turbotoken-boundary-class-${fixture.id}-auto`,
      fixture.path,
      "turbotoken_count_ascii_class_boundaries_utf8",
    ),
    benchCommand(
      `turbotoken-boundary-class-${fixture.id}-scalar`,
      fixture.path,
      "turbotoken_count_ascii_class_boundaries_utf8_scalar",
    ),
  );
}

const neonProbe = runShell(
  `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();sys.exit(0 if int(lib.turbotoken_count_ascii_class_boundaries_utf8_neon(data,len(data))) >= 0 else 1)"`,
  { allowFailure: true },
);

if (neonProbe.code === 0) {
  for (const fixture of fixtures) {
    commands.push(
      benchCommand(
        `turbotoken-boundary-class-${fixture.id}-neon`,
        fixture.path,
        "turbotoken_count_ascii_class_boundaries_utf8_neon",
      ),
    );
  }
} else {
  console.warn("NEON boundary-classifier symbol unavailable; benchmark will skip explicit neon command.");
}

process.exit(
  runBench({
    name: "bench-boundary-classifier",
    commands,
    metadata: {
      fixtures,
      iterationsPerSample: iterations,
      includesNeon: neonProbe.code === 0,
      note: "native ASCII boundary-classification counters (auto/scalar/neon) on mixed-ascii and non-ascii-heavy fixtures",
    },
  }),
);
