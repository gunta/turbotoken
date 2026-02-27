#!/usr/bin/env bun
import { runBench } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable, resolvePath, section, writeJson } from "./_lib";

section("GPU benchmark");
const python = pythonExecutable();
ensureFixtures();

const probeResult = Bun.spawnSync({
  cmd: [
    python,
    "-c",
    "import json,sys;sys.path.insert(0,'python');from turbotoken import _gpu;print(json.dumps(_gpu.backend_info()))",
  ],
  cwd: resolvePath(),
  stdout: "pipe",
  stderr: "pipe",
});

const outputPath = resolvePath("bench", "results", `bench-gpu-${Date.now()}.json`);
const probeStdout = new TextDecoder().decode(probeResult.stdout).trim();
const probeStderr = new TextDecoder().decode(probeResult.stderr).trim();

if (probeResult.exitCode !== 0 || probeStdout.length === 0) {
  const payload = {
    tool: "gpu-bench",
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: probeStderr || "failed to probe GPU backend",
  };
  writeJson(outputPath, payload);
  console.log("GPU backend probe failed; wrote skip record.");
  process.exit(0);
}

let probe: Record<string, unknown>;
try {
  probe = JSON.parse(probeStdout) as Record<string, unknown>;
} catch {
  const payload = {
    tool: "gpu-bench",
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: "GPU backend probe returned invalid JSON",
    raw: probeStdout,
  };
  writeJson(outputPath, payload);
  console.log("GPU backend probe returned invalid JSON; wrote skip record.");
  process.exit(0);
}

if (probe.available !== true) {
  const payload = {
    tool: "gpu-bench",
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason:
      typeof probe.error === "string"
        ? probe.error
        : "GPU backend reports unavailable",
    probe,
  };
  writeJson(outputPath, payload);
  console.log("GPU backend unavailable; wrote skip record.");
  process.exit(0);
}

const nativeProbe = Bun.spawnSync({
  cmd: [
    python,
    "-c",
    "import sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();raise SystemExit(0 if bridge.available else 1)",
  ],
  cwd: resolvePath(),
  stdout: "pipe",
  stderr: "pipe",
});
const includeNativeBaseline = nativeProbe.exitCode === 0;

const singleIterations = 128;
const batchIterations = 512;

const commands: { name: string; command: string }[] = [
  {
    name: "turbotoken-metal-encode-utf8-bytes-1mb",
    command:
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import _gpu;bridge=_gpu.get_metal_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();in_buf=ffi.from_buffer('const unsigned char[]',data);out=ffi.new('uint32_t[]',len(data));iters=${singleIterations};written=0\nfor _ in range(iters):\n written=int(lib.turbotoken_metal_encode_utf8_bytes(in_buf,len(data),out,len(data)))\nassert written==len(data)"`,
  },
  {
    name: "turbotoken-metal-count-nonzero-batch-4096x1kb",
    command:
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import _gpu;bridge=_gpu.get_metal_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;chunk=pathlib.Path('bench/fixtures/english-1kb.txt').read_bytes();batch=4096;merged=chunk*batch;offsets=[i*len(chunk) for i in range(batch+1)];merged_buf=ffi.from_buffer('const unsigned char[]',merged);offset_buf=ffi.new('uint32_t[]',offsets);out=ffi.new('uint32_t[]',batch);iters=${batchIterations};written=0\nfor _ in range(iters):\n written=int(lib.turbotoken_metal_count_nonzero_segments(merged_buf,len(merged),offset_buf,len(offsets),out,batch))\nassert written==batch\nassert int(out[0])==len(chunk)"`,
  },
  {
    name: "python-cpu-count-nonzero-batch-4096x1kb",
    command:
      `${python} -c "import pathlib;chunk=pathlib.Path('bench/fixtures/english-1kb.txt').read_bytes();batch=4096;payload=[chunk]*batch;iters=${batchIterations};counts=[]\nfor _ in range(iters):\n counts=[len(item)-item.count(0) for item in payload]\nassert counts and counts[0]==len(chunk)"`,
  },
];

if (includeNativeBaseline) {
  commands.splice(1, 0, {
    name: "turbotoken-native-neon-encode-utf8-bytes-1mb",
    command:
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();out=ffi.new('uint32_t[]',len(data));iters=${singleIterations};written=0\nfor _ in range(iters):\n written=int(lib.turbotoken_encode_utf8_bytes(data,len(data),out,len(data)))\nassert written==len(data)"`,
  });
  commands.splice(2, 0, {
    name: "turbotoken-hybrid-neon-metal-encode-utf8-bytes-1mb",
    command:
      `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import _gpu;gbridge=_gpu.get_metal_bridge();assert gbridge.available,gbridge.error;ffi=gbridge._ffi;lib=gbridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();split=len(data)//2;in_buf=ffi.from_buffer('const unsigned char[]',data);out=ffi.new('uint32_t[]',len(data));iters=${singleIterations};written=0\nfor _ in range(iters):\n written=int(lib.turbotoken_metal_encode_utf8_bytes_hybrid(in_buf,len(data),split,out,len(data)))\nassert written==len(data)"`,
  });
}

process.exit(
  runBench({
    name: "bench-gpu",
    commands,
    metadata: {
      fixtureEncode: "bench/fixtures/english-1mb.txt",
      fixtureBatch: "bench/fixtures/english-1kb.txt",
      encodeIterationsPerSample: singleIterations,
      batchIterationsPerSample: batchIterations,
      encodeTotalBytesPerSample: singleIterations * 1_048_576,
      countBatchTotalBytesPerSample: batchIterations * 4_096 * 1_024,
      backend: "apple-metal",
      note: "Experimental Metal backend benchmarks UTF-8 byte-path kernels only (full GPU BPE merge path is still pending).",
      probe,
      includeNativeBaseline,
    },
  }),
);
