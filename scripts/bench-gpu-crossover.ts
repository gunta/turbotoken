#!/usr/bin/env bun
import { pythonExecutable, resolvePath, section, writeJson } from "./_lib";

section("GPU crossover matrix benchmark");
const python = pythonExecutable();

const longModeRaw = (process.env.TURBOTOKEN_BENCH_LONG ?? "0").trim().toLowerCase();
const longBenchmarkEnabled =
  longModeRaw === "1" ||
  longModeRaw === "true" ||
  longModeRaw === "yes" ||
  longModeRaw === "on";
const longBenchmarkEnabledPy = longBenchmarkEnabled ? "True" : "False";
const longChars = 10_485_760;

const encodeSizes = longBenchmarkEnabled
  ? [1024, 4096, 16384, 65536, 262144, 1048576, longChars]
  : [1024, 4096, 16384, 65536, 262144, 1048576];

const bpeSizes = longBenchmarkEnabled
  ? [65536, 262144, 1048576, longChars]
  : [65536, 262144, 1048576];

if (longBenchmarkEnabled) {
  console.log(
    `Long mode enabled via TURBOTOKEN_BENCH_LONG=${process.env.TURBOTOKEN_BENCH_LONG}; appending ${longChars.toLocaleString()}-char benchmark row`,
  );
}

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

const outputPath = resolvePath("bench", "results", `bench-gpu-crossover-${Date.now()}.json`);
const probeStdout = new TextDecoder().decode(probeResult.stdout).trim();
const probeStderr = new TextDecoder().decode(probeResult.stderr).trim();

if (probeResult.exitCode !== 0 || probeStdout.length === 0) {
  writeJson(outputPath, {
    tool: "gpu-crossover-bench",
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: probeStderr || "failed to probe gpu backend",
  });
  console.log(`GPU crossover probe failed; wrote skip record: ${outputPath}`);
  process.exit(0);
}

let probe: Record<string, unknown>;
try {
  probe = JSON.parse(probeStdout) as Record<string, unknown>;
} catch {
  writeJson(outputPath, {
    tool: "gpu-crossover-bench",
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: "invalid JSON from gpu backend probe",
    raw: probeStdout,
  });
  console.log(`GPU crossover probe returned invalid JSON; wrote skip record: ${outputPath}`);
  process.exit(0);
}

if (probe.available !== true) {
  writeJson(outputPath, {
    tool: "gpu-crossover-bench",
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: typeof probe.error === "string" ? probe.error : "gpu backend unavailable",
    probe,
  });
  console.log(`GPU backend unavailable; wrote skip record: ${outputPath}`);
  process.exit(0);
}

const matrixScript = `
import json,os,sys,time
sys.path.insert(0,'python')
from turbotoken import _gpu
from turbotoken import get_encoding
from turbotoken._native import get_native_bridge

bridge=_gpu.get_metal_bridge()
native=get_native_bridge()
enc=get_encoding("o200k_base")

def mean_ms(fn, loops):
    start=time.perf_counter()
    for _ in range(loops):
        fn()
    return (time.perf_counter()-start)*1000.0/max(1,loops)

def mib_per_s(total_bytes, mean_ms):
    if mean_ms <= 0:
        return None
    return (total_bytes / (1024.0 * 1024.0)) / (mean_ms / 1000.0)

def encode_metal_forced(piece_text):
    prev=os.environ.get('TURBOTOKEN_METAL_FORCE_ALL_PIECES')
    os.environ['TURBOTOKEN_METAL_FORCE_ALL_PIECES']='1'
    try:
        return enc.encode_gpu(
            [piece_text],
            device='metal',
            chunk_bytes=4096,
            overlap_bytes=512,
            strict_verify=False,
        )[0]
    finally:
        if prev is None:
            os.environ.pop('TURBOTOKEN_METAL_FORCE_ALL_PIECES', None)
        else:
            os.environ['TURBOTOKEN_METAL_FORCE_ALL_PIECES']=prev

encode_sizes=${JSON.stringify(encodeSizes)}
encode_rows=[]
for size in encode_sizes:
    loops=max(8,min(256,(16*1048576)//size))
    payload=bytes(((i%251)+1) for i in range(size))
    metal_ms=mean_ms(lambda: bridge.encode_utf8_bytes(payload), loops)
    native_ms=None
    if native.available:
        native_ms=mean_ms(lambda: native.encode_utf8_bytes(payload), loops)
    auto_tokens,auto_backend=_gpu.encode_utf8_bytes_auto(payload)
    profile=_gpu.profile_last()
    encode_rows.append({
        "bytes":size,
        "loops":loops,
        "metal_mean_ms":metal_ms,
        "metal_mib_per_s":mib_per_s(size, metal_ms),
        "native_mean_ms":native_ms,
        "native_mib_per_s":mib_per_s(size, native_ms) if native_ms is not None else None,
        "auto_backend":auto_backend,
        "auto_tokens_len":len(auto_tokens) if auto_tokens is not None else None,
        "last_profile":profile,
    })

segment=b'a'*1024
count_batches=[64,128,256,512,1024,2048,4096,8192]
count_rows=[]
for batch_size in count_batches:
    loops=max(8,min(256,(16*8192)//batch_size))
    payload=[segment]*batch_size
    metal_ms=mean_ms(lambda: bridge.count_nonzero_bytes_batch(payload), loops)
    py_ms=mean_ms(lambda: [len(item)-item.count(0) for item in payload], loops)
    auto_counts,auto_backend=_gpu.count_nonzero_bytes_batch_auto(payload)
    profile=_gpu.profile_last()
    count_rows.append({
        "batch":batch_size,
        "segment_bytes":len(segment),
        "total_bytes":batch_size*len(segment),
        "loops":loops,
        "metal_mean_ms":metal_ms,
        "metal_mib_per_s":mib_per_s(batch_size*len(segment), metal_ms),
        "python_mean_ms":py_ms,
        "python_mib_per_s":mib_per_s(batch_size*len(segment), py_ms),
        "auto_backend":auto_backend,
        "auto_counts_head":auto_counts[:2] if auto_counts is not None else None,
        "last_profile":profile,
    })

route=_gpu.calibrate_autoroute(force=True)
bpe_sizes=${JSON.stringify(bpeSizes)}
bpe_rows=[]
for size in bpe_sizes:
    loops=max(2,min(8,(2*1048576)//size))
    text='a'*size
    baseline=enc.encode(text)
    route_backend=_gpu.bpe_route_backend(len(text.encode('utf-8')))
    auto_tokens=enc.encode_gpu(
        [text],
        device='auto',
        chunk_bytes=4096,
        overlap_bytes=512,
        strict_verify=False,
    )[0]
    metal_tokens=encode_metal_forced(text)
    cpu_ms=mean_ms(lambda: enc.encode(text), loops)
    auto_ms=mean_ms(
        lambda: enc.encode_gpu(
            [text],
            device='auto',
            chunk_bytes=4096,
            overlap_bytes=512,
            strict_verify=False,
        ),
        loops,
    )
    metal_ms=mean_ms(lambda: encode_metal_forced(text), loops)
    bpe_rows.append({
        "chars":size,
        "bytes":size,
        "route_backend":route_backend,
        "loops":loops,
        "cpu_encode_ms":cpu_ms,
        "cpu_encode_mib_per_s":mib_per_s(size, cpu_ms),
        "auto_gpu_ms":auto_ms,
        "auto_gpu_mib_per_s":mib_per_s(size, auto_ms),
        "metal_gpu_ms":metal_ms,
        "metal_gpu_mib_per_s":mib_per_s(size, metal_ms),
        "auto_matches_baseline":auto_tokens==baseline,
        "metal_matches_baseline":metal_tokens==baseline,
        "auto_tokens_len":len(auto_tokens),
        "baseline_tokens_len":len(baseline),
        "metal_tokens_len":len(metal_tokens),
    })

print(json.dumps({
    "tool":"gpu-crossover-bench",
    "generated_at":time.time(),
    "long_mode":{
        "enabled":${longBenchmarkEnabledPy},
        "flag":"TURBOTOKEN_BENCH_LONG",
        "long_chars":${longChars},
    },
    "bench_sizes":{
        "encode_bytes":encode_sizes,
        "count_batches":count_batches,
        "bpe_chars":bpe_sizes,
    },
    "probe":_gpu.backend_info(),
    "native_available":native.available,
    "encode_rows":encode_rows,
    "count_rows":count_rows,
    "bpe_rows":bpe_rows,
    "autoroute":route,
}))
`;

const runResult = Bun.spawnSync({
  cmd: [python, "-c", matrixScript],
  cwd: resolvePath(),
  stdout: "pipe",
  stderr: "pipe",
});

if (runResult.exitCode !== 0) {
  writeJson(outputPath, {
    tool: "gpu-crossover-bench",
    generatedAt: new Date().toISOString(),
    status: "failed",
    probe,
    stderr: new TextDecoder().decode(runResult.stderr).trim(),
  });
  console.log(`GPU crossover benchmark failed; wrote failure record: ${outputPath}`);
  process.exit(1);
}

const matrixStdout = new TextDecoder().decode(runResult.stdout).trim();
let payload: Record<string, unknown>;
try {
  payload = JSON.parse(matrixStdout) as Record<string, unknown>;
} catch {
  writeJson(outputPath, {
    tool: "gpu-crossover-bench",
    generatedAt: new Date().toISOString(),
    status: "failed",
    reason: "matrix runner returned invalid JSON",
    raw: matrixStdout,
  });
  console.log(`GPU crossover benchmark returned invalid JSON; wrote failure record: ${outputPath}`);
  process.exit(1);
}

writeJson(outputPath, payload);
console.log(`Wrote GPU crossover benchmark matrix: ${outputPath}`);
