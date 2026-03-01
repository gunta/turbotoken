#!/usr/bin/env bun
import { ensureFixtures } from "./_fixtures";
import { acquireBenchmarkLock, pythonExecutable, resolvePath, section, writeJson } from "./_lib";

section("GPU crossover matrix benchmark");
acquireBenchmarkLock({ label: "bench-gpu-crossover" });
const python = pythonExecutable();
ensureFixtures();

const longModeRaw = (process.env.TURBOTOKEN_BENCH_LONG ?? "0").trim().toLowerCase();
const longBenchmarkEnabled =
  longModeRaw === "1" ||
  longModeRaw === "true" ||
  longModeRaw === "yes" ||
  longModeRaw === "on";
const longBenchmarkEnabledPy = longBenchmarkEnabled ? "True" : "False";
const longChars = 10_485_760;
const quickModeRaw = (process.env.TURBOTOKEN_GPU_CROSSOVER_QUICK ?? "0").trim().toLowerCase();
const quickModeEnabled =
  quickModeRaw === "1" ||
  quickModeRaw === "true" ||
  quickModeRaw === "yes" ||
  quickModeRaw === "on";
const quickModeEnabledPy = quickModeEnabled ? "True" : "False";
const calibrateForcePy = quickModeEnabled ? "False" : "True";
const bpeTextKindRaw = (process.env.TURBOTOKEN_GPU_CROSSOVER_BPE_TEXT_KIND ?? "low-entropy").trim().toLowerCase();
const bpeTextKind = bpeTextKindRaw === "normal-text" || bpeTextKindRaw === "normal" ? "normal-text" : "low-entropy";

const encodeSizes = longBenchmarkEnabled
  ? [1024, 4096, 16384, 65536, 262144, 1048576, longChars]
  : quickModeEnabled
    ? [262144]
    : [1024, 4096, 16384, 65536, 262144, 1048576];

const bpeSizes = longBenchmarkEnabled
  ? [65536, 262144, 1048576, longChars]
  : quickModeEnabled
    ? [262144]
    : [65536, 262144, 1048576];
const countBatches = quickModeEnabled ? [2048] : [64, 128, 256, 512, 1024, 2048, 4096, 8192];
const encodeLoopBaseMiB = quickModeEnabled ? 4 : 16;
const countLoopBaseBatches = quickModeEnabled ? 4 : 16;
const bpeLoopBaseMiB = quickModeEnabled ? 1 : 2;

if (longBenchmarkEnabled) {
  console.log(
    `Long mode enabled via TURBOTOKEN_BENCH_LONG=${process.env.TURBOTOKEN_BENCH_LONG}; appending ${longChars.toLocaleString()}-char benchmark row`,
  );
}
if (quickModeEnabled) {
  console.log(
    `Quick mode enabled via TURBOTOKEN_GPU_CROSSOVER_QUICK=${process.env.TURBOTOKEN_GPU_CROSSOVER_QUICK}; using reduced loop counts for A/B checks`,
  );
}
console.log(`BPE text profile: ${bpeTextKind} (set TURBOTOKEN_GPU_CROSSOVER_BPE_TEXT_KIND=low-entropy|normal-text)`);

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
import json,os,pathlib,sys,time
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
    loops=max(1,min(256,(${encodeLoopBaseMiB}*1048576)//size))
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
count_batches=${JSON.stringify(countBatches)}
count_rows=[]
for batch_size in count_batches:
    loops=max(1,min(256,(${countLoopBaseBatches}*8192)//batch_size))
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

route=_gpu.calibrate_autoroute(force=${calibrateForcePy})
bpe_sizes=${JSON.stringify(bpeSizes)}
bpe_text_kind=${JSON.stringify(bpeTextKind)}
fixture_text=bytes(pathlib.Path("bench/fixtures/english-1mb.txt").read_bytes())
if len(fixture_text) == 0:
    fixture_text=b"The quick brown fox jumps over the lazy dog. "

def build_bpe_text(size):
    if bpe_text_kind == "normal-text":
        repeats=max(1,(size+len(fixture_text)-1)//len(fixture_text))
        payload=(fixture_text*repeats)[:size]
        return payload.decode("utf-8", "ignore")
    return 'a'*size

bpe_rows=[]
for size in bpe_sizes:
    text=build_bpe_text(size)
    data=text.encode('utf-8')
    input_bytes=max(1,len(data))
    loops=max(1,min(8,(${bpeLoopBaseMiB}*1048576)//input_bytes))
    baseline=enc.encode(text)
    route_backend=_gpu.bpe_route_backend(input_bytes)
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
    metal_profile=_gpu.profile_last() or {}
    bpe_rows.append({
        "chars":len(text),
        "bytes":input_bytes,
        "text_kind":bpe_text_kind,
        "route_backend":route_backend,
        "loops":loops,
        "cpu_encode_ms":cpu_ms,
        "cpu_encode_mib_per_s":mib_per_s(input_bytes, cpu_ms),
        "auto_gpu_ms":auto_ms,
        "auto_gpu_mib_per_s":mib_per_s(input_bytes, auto_ms),
        "metal_gpu_ms":metal_ms,
        "metal_gpu_mib_per_s":mib_per_s(input_bytes, metal_ms),
        "auto_matches_baseline":auto_tokens==baseline,
        "metal_matches_baseline":metal_tokens==baseline,
        "auto_tokens_len":len(auto_tokens),
        "baseline_tokens_len":len(baseline),
        "metal_tokens_len":len(metal_tokens),
        "metal_bpe_rounds":int(metal_profile.get("bpe_rounds",0)),
        "metal_bpe_submits":int(metal_profile.get("bpe_submits",0)),
        "metal_last_profile":metal_profile,
    })

print(json.dumps({
    "tool":"gpu-crossover-bench",
    "generated_at":time.time(),
    "long_mode":{
        "enabled":${longBenchmarkEnabledPy},
        "flag":"TURBOTOKEN_BENCH_LONG",
        "long_chars":${longChars},
    },
    "quick_mode":{
        "enabled":${quickModeEnabledPy},
        "flag":"TURBOTOKEN_GPU_CROSSOVER_QUICK",
    },
    "bpe_text_profile":{
        "kind":bpe_text_kind,
        "source_fixture":"bench/fixtures/english-1mb.txt",
        "flag":"TURBOTOKEN_GPU_CROSSOVER_BPE_TEXT_KIND",
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
