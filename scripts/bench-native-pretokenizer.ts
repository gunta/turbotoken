#!/usr/bin/env bun
import { runBench } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable, runShell } from "./_lib";

ensureFixtures();
const python = pythonExecutable();
const iterations = 256;

const commands = [
  {
    name: "turbotoken-native-count-non-ascii-1mb-auto",
    command:
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();expected=sum((b>>7) for b in data);iters=${iterations};count=0\nfor _ in range(iters):\n count=int(lib.turbotoken_count_non_ascii_utf8(data,len(data)))\nassert count==expected"`,
  },
  {
    name: "turbotoken-native-count-non-ascii-1mb-scalar",
    command:
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();expected=sum((b>>7) for b in data);iters=${iterations};count=0\nfor _ in range(iters):\n count=int(lib.turbotoken_count_non_ascii_utf8_scalar(data,len(data)))\nassert count==expected"`,
  },
  {
    name: "turbotoken-native-count-non-ascii-1mb-neon",
    command:
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();expected=sum((b>>7) for b in data);iters=${iterations};count=0\nfor _ in range(iters):\n count=int(lib.turbotoken_count_non_ascii_utf8_neon(data,len(data)))\nassert count==expected"`,
  },
];

const dotprodProbe = runShell(
  `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();sys.exit(0 if int(lib.turbotoken_count_non_ascii_utf8_dotprod(data,len(data))) >= 0 else 1)"`,
  { allowFailure: true },
);

if (dotprodProbe.code === 0) {
  commands.push({
    name: "turbotoken-native-count-non-ascii-1mb-dotprod",
    command:
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();expected=sum((b>>7) for b in data);iters=${iterations};count=0\nfor _ in range(iters):\n count=int(lib.turbotoken_count_non_ascii_utf8_dotprod(data,len(data)))\nassert count==expected"`,
  });
} else {
  console.warn("DotProd kernel is unavailable for this build/target; benchmark will skip explicit dotprod command.");
}

process.exit(
  runBench({
    name: "bench-native-pretokenizer",
    commands,
    metadata: {
      fixture: "bench/fixtures/english-1mb.txt",
      iterationsPerSample: iterations,
      includesDotProd: dotprodProbe.code === 0,
      note: "native C ABI non-ascii byte counting with auto-dispatch vs scalar/neon/dotprod kernels",
    },
  }),
);
