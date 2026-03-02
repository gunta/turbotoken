#!/usr/bin/env bun
import { ensureFixtures } from "./_fixtures";
import { acquireBenchmarkLock, benchSpeedProfile, pythonExecutable, resolvePath, section, writeJson } from "./_lib";

section("GPU overlap benchmark (CPU pretokenize + Metal overlap)");
acquireBenchmarkLock({ label: "bench-gpu-overlap" });
ensureFixtures();

const python = pythonExecutable();
const speedProfile = benchSpeedProfile();
const runsRaw = process.env.TURBOTOKEN_GPU_OVERLAP_RUNS?.trim();
const runs = runsRaw ? Math.max(1, Number.parseInt(runsRaw, 10) || 3) : 3;
const batchRaw = process.env.TURBOTOKEN_GPU_OVERLAP_BATCH?.trim();
const batch = batchRaw ? Math.max(1, Number.parseInt(batchRaw, 10) || 4) : 4;
const textMiBRaw = process.env.TURBOTOKEN_GPU_OVERLAP_TEXT_MIB?.trim();
const defaultTextMiB = speedProfile === "fast" ? 0.125 : 0.25;
const textMiB = textMiBRaw
  ? Math.max(0.125, Number.parseFloat(textMiBRaw) || defaultTextMiB)
  : defaultTextMiB;
const textKindRaw = process.env.TURBOTOKEN_GPU_OVERLAP_TEXT_KIND?.trim().toLowerCase();
const textKind = textKindRaw === "low-entropy" ? "low-entropy" : "normal-text";
const chunkBytesRaw = process.env.TURBOTOKEN_GPU_OVERLAP_CHUNK_BYTES?.trim();
const chunkBytes = chunkBytesRaw ? Math.max(256, Number.parseInt(chunkBytesRaw, 10) || 1024) : 1024;
const fixturePath = resolvePath("bench", "fixtures", "english-1mb.txt");

const outputPath = resolvePath("bench", "results", `bench-gpu-overlap-${Date.now()}.json`);

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

const probeStdout = new TextDecoder().decode(probeResult.stdout).trim();
const probeStderr = new TextDecoder().decode(probeResult.stderr).trim();
if (probeResult.exitCode !== 0 || probeStdout.length === 0) {
  writeJson(outputPath, {
    tool: "gpu-overlap-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "skipped",
    reason: probeStderr || "failed to probe gpu backend",
  });
  console.log(`GPU overlap probe failed; wrote skip record: ${outputPath}`);
  process.exit(0);
}

let probe: Record<string, unknown>;
try {
  probe = JSON.parse(probeStdout) as Record<string, unknown>;
} catch {
  writeJson(outputPath, {
    tool: "gpu-overlap-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "skipped",
    reason: "invalid JSON from gpu backend probe",
    raw: probeStdout,
  });
  console.log(`GPU overlap probe returned invalid JSON; wrote skip record: ${outputPath}`);
  process.exit(0);
}

if (probe.available !== true) {
  writeJson(outputPath, {
    tool: "gpu-overlap-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "skipped",
    reason: typeof probe.error === "string" ? probe.error : "gpu backend unavailable",
    probe,
  });
  console.log(`GPU backend unavailable; wrote skip record: ${outputPath}`);
  process.exit(0);
}

const py = `
import json,os,sys,time
sys.path.insert(0,'python')
from turbotoken import _gpu,get_encoding

runs=int(sys.argv[1])
batch_size=int(sys.argv[2])
text_mib=max(0.125,float(sys.argv[3]))
chunk_bytes=max(256,int(sys.argv[4]))
text_kind=str(sys.argv[5] if len(sys.argv) > 5 else 'normal-text').strip().lower()
fixture_path=str(sys.argv[6] if len(sys.argv) > 6 else '')
enc=get_encoding('o200k_base')
target_bytes=max(1,int(text_mib*1024*1024))
if text_kind == 'low-entropy':
    text="a"*target_bytes
else:
    payload=b""
    if fixture_path:
        try:
            with open(fixture_path, "rb") as fh:
                payload=fh.read()
        except Exception:
            payload=b""
    if not payload:
        payload=(b"The quick brown fox jumps over the lazy dog. " * 2048)
    normal_stream=bytes(ch for ch in payload if (65 <= ch <= 90) or (97 <= ch <= 122))
    if not normal_stream:
        normal_stream=b"TheQuickBrownFoxJumpsOverTheLazyDog"
    normal_stream_lower=bytes(((ch + 32) if (65 <= ch <= 90) else ch) for ch in normal_stream)
    repeats=(target_bytes + len(normal_stream_lower) - 1)//len(normal_stream_lower)
    text_bytes=(normal_stream_lower*repeats)[:target_bytes]
    text=text_bytes.decode("ascii", errors="ignore")
texts=[text]*batch_size
piece_bytes=len(text.encode('utf-8'))
total_bytes=piece_bytes*batch_size
MEMORY_KEYS=(
    "memory_active_bytes",
    "memory_working_set_bytes",
    "memory_device_allocated_bytes",
    "memory_device_recommended_working_set_bytes",
)

def encode_gpu_metal(overlap_enabled):
    prev_force=os.environ.get('TURBOTOKEN_METAL_FORCE_ALL_PIECES')
    prev_force_strict=os.environ.get('TURBOTOKEN_METAL_FORCE_ALL_PIECES_STRICT')
    prev_overlap=os.environ.get('TURBOTOKEN_GPU_OVERLAP_ENABLE')
    prev_overlap_min_total=os.environ.get('TURBOTOKEN_GPU_OVERLAP_MIN_TOTAL_INPUT_BYTES')
    os.environ['TURBOTOKEN_METAL_FORCE_ALL_PIECES']='1'
    os.environ['TURBOTOKEN_METAL_FORCE_ALL_PIECES_STRICT']='1'
    os.environ['TURBOTOKEN_GPU_OVERLAP_ENABLE']='1' if overlap_enabled else '0'
    if overlap_enabled:
        os.environ['TURBOTOKEN_GPU_OVERLAP_MIN_TOTAL_INPUT_BYTES']='0'
    try:
        return enc.encode_gpu(
            texts,
            device='metal',
            chunk_bytes=chunk_bytes,
            overlap_bytes=512,
            strict_verify=False,
            num_threads=1,
        )
    finally:
        if prev_force is None:
            os.environ.pop('TURBOTOKEN_METAL_FORCE_ALL_PIECES', None)
        else:
            os.environ['TURBOTOKEN_METAL_FORCE_ALL_PIECES']=prev_force
        if prev_force_strict is None:
            os.environ.pop('TURBOTOKEN_METAL_FORCE_ALL_PIECES_STRICT', None)
        else:
            os.environ['TURBOTOKEN_METAL_FORCE_ALL_PIECES_STRICT']=prev_force_strict
        if prev_overlap is None:
            os.environ.pop('TURBOTOKEN_GPU_OVERLAP_ENABLE', None)
        else:
            os.environ['TURBOTOKEN_GPU_OVERLAP_ENABLE']=prev_overlap
        if prev_overlap_min_total is None:
            os.environ.pop('TURBOTOKEN_GPU_OVERLAP_MIN_TOTAL_INPUT_BYTES', None)
        else:
            os.environ['TURBOTOKEN_GPU_OVERLAP_MIN_TOTAL_INPUT_BYTES']=prev_overlap_min_total

# Keep one correctness check for each route mode before timing.
baseline_tokens=enc.encode_batch(texts, num_threads=1)
metal_no_overlap=encode_gpu_metal(False)
metal_overlap=encode_gpu_metal(True)

if metal_no_overlap != baseline_tokens or metal_overlap != baseline_tokens:
    raise RuntimeError('gpu overlap path diverged from baseline output')

def mean_ms(fn, loops):
    start=time.perf_counter()
    for _ in range(max(1, loops)):
        fn()
    return (time.perf_counter()-start)*1000.0/max(1, loops)

def bench_gpu_mode(overlap_enabled, loops):
    memory_samples=[]
    start=time.perf_counter()
    for _ in range(max(1, loops)):
        encode_gpu_metal(overlap_enabled)
        profile=_gpu.profile_last() or {}
        sample={}
        for key in MEMORY_KEYS:
            sample[key]=int(profile.get(key, 0))
        memory_samples.append(sample)
    elapsed_ms=(time.perf_counter()-start)*1000.0/max(1, loops)
    max_memory={}
    for key in MEMORY_KEYS:
        values=[sample[key] for sample in memory_samples]
        max_memory[f"max_{key}"]=max(values) if values else None
    return elapsed_ms, max_memory

def mib_per_s(ms):
    if ms <= 0:
        return None
    return (total_bytes/(1024.0*1024.0))/(ms/1000.0)

cpu_ms=mean_ms(lambda: enc.encode_batch(texts, num_threads=1), runs)
metal_no_overlap_ms,metal_no_overlap_mem=bench_gpu_mode(False, runs)
metal_overlap_ms,metal_overlap_mem=bench_gpu_mode(True, runs)
route_backend_auto=_gpu.bpe_route_backend(piece_bytes)
profile=_gpu.profile_last()

print(json.dumps({
    'tool':'gpu-overlap-bench',
    'generated_at':time.time(),
    'runs_per_row':runs,
    'batch_size':batch_size,
    'text_mib':text_mib,
    'text_kind':text_kind,
    'fixture_path':fixture_path or None,
    'chunk_bytes':chunk_bytes,
    'piece_bytes':piece_bytes,
    'total_bytes':total_bytes,
    'route_backend_auto':route_backend_auto,
    'route_backend_forced':'metal',
    'probe':_gpu.backend_info(),
    'rows':[
        {
            'name':'cpu-only-encode-batch',
            'mean_ms':cpu_ms,
            'mib_per_s':mib_per_s(cpu_ms),
        },
        {
            'name':'gpu-metal-no-overlap',
            'mean_ms':metal_no_overlap_ms,
            'mib_per_s':mib_per_s(metal_no_overlap_ms),
            **metal_no_overlap_mem,
        },
        {
            'name':'gpu-metal-cpu-overlap',
            'mean_ms':metal_overlap_ms,
            'mib_per_s':mib_per_s(metal_overlap_ms),
            **metal_overlap_mem,
        },
    ],
    'speedups':{
        'overlap_vs_cpu': (cpu_ms/metal_overlap_ms) if metal_overlap_ms > 0 else None,
        'overlap_vs_no_overlap': (metal_no_overlap_ms/metal_overlap_ms) if metal_overlap_ms > 0 else None,
    },
    'last_profile':profile,
    'note':'Compares CPU-only encode_batch with Metal encode_gpu in non-overlap and CPU+GPU overlap modes. GPU rows include max memory telemetry from _gpu.profile_last() samples.',
}))
`;

const runResult = Bun.spawnSync({
  cmd: [
    python,
    "-c",
    py,
    String(runs),
    String(batch),
    String(textMiB),
    String(chunkBytes),
    textKind,
    fixturePath,
  ],
  cwd: resolvePath(),
  stdout: "pipe",
  stderr: "pipe",
});

if (runResult.exitCode !== 0) {
  writeJson(outputPath, {
    tool: "gpu-overlap-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "failed",
    probe,
    stderr: new TextDecoder().decode(runResult.stderr).trim(),
  });
  console.log(`GPU overlap benchmark failed; wrote failure record: ${outputPath}`);
  process.exit(1);
}

const runStdout = new TextDecoder().decode(runResult.stdout).trim();
let payload: Record<string, unknown>;
try {
  payload = JSON.parse(runStdout) as Record<string, unknown>;
} catch {
  writeJson(outputPath, {
    tool: "gpu-overlap-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "failed",
    reason: "runner returned invalid JSON",
    raw: runStdout,
  });
  console.log(`GPU overlap benchmark returned invalid JSON; wrote failure record: ${outputPath}`);
  process.exit(1);
}

writeJson(outputPath, {
  ...payload,
  speedProfile,
});
console.log(`Wrote GPU overlap benchmark: ${outputPath}`);
