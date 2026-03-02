#!/usr/bin/env bun
import { ensureFixtures } from "./_fixtures";
import { acquireBenchmarkLock, benchSpeedProfile, pythonExecutable, resolvePath, section, writeJson } from "./_lib";

section("GPU memory benchmark");
acquireBenchmarkLock({ label: "bench-gpu-memory" });
ensureFixtures();

const python = pythonExecutable();
const speedProfile = benchSpeedProfile();
const runsRaw = process.env.TURBOTOKEN_GPU_MEMORY_RUNS?.trim();
const runs = runsRaw ? Math.max(1, Number.parseInt(runsRaw, 10) || 5) : 5;

const outputPath = resolvePath("bench", "results", `bench-gpu-memory-${Date.now()}.json`);

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
    tool: "gpu-memory-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "skipped",
    reason: probeStderr || "failed to probe gpu backend",
  });
  console.log(`GPU memory probe failed; wrote skip record: ${outputPath}`);
  process.exit(0);
}

let probe: Record<string, unknown>;
try {
  probe = JSON.parse(probeStdout) as Record<string, unknown>;
} catch {
  writeJson(outputPath, {
    tool: "gpu-memory-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "skipped",
    reason: "invalid JSON from gpu backend probe",
    raw: probeStdout,
  });
  console.log(`GPU memory probe returned invalid JSON; wrote skip record: ${outputPath}`);
  process.exit(0);
}

if (probe.available !== true) {
  writeJson(outputPath, {
    tool: "gpu-memory-bench",
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
import json,os,pathlib,statistics,sys,time
sys.path.insert(0,'python')
from turbotoken import _gpu,get_encoding

runs=int(sys.argv[1])
bridge=_gpu.get_metal_bridge()
skip_direct_kernel=os.environ.get("TURBOTOKEN_GPU_MEMORY_SKIP_DIRECT_KERNEL","").strip().lower() in {"1","true","yes","on"}
route_bytes_raw=os.environ.get("TURBOTOKEN_GPU_MEMORY_ROUTE_BYTES","").strip()
route_text_kind_raw=os.environ.get("TURBOTOKEN_GPU_MEMORY_ROUTE_TEXT_KIND","low-entropy").strip().lower()
route_text_kind="normal-text" if route_text_kind_raw in {"normal","normal-text"} else "low-entropy"

def summarize(name,workload,samples):
    keys=[
        "gpu_ns",
        "cpu_ns",
        "bpe_rounds",
        "bpe_submits",
        "memory_active_bytes",
        "memory_working_set_bytes",
        "memory_device_allocated_bytes",
        "memory_device_recommended_working_set_bytes",
    ]
    summary={"name":name,"workload":workload,"runs":len(samples),"samples":samples}
    total_bytes=workload.get("total_bytes")
    if not isinstance(total_bytes,int) or total_bytes <= 0:
        input_bytes=workload.get("input_bytes")
        if isinstance(input_bytes,int) and input_bytes > 0:
            total_bytes=input_bytes
        else:
            segment_bytes=workload.get("segment_bytes")
            batch=workload.get("batch")
            if isinstance(segment_bytes,int) and isinstance(batch,int) and segment_bytes > 0 and batch > 0:
                total_bytes=segment_bytes*batch
            else:
                total_bytes=0
    for key in keys:
        vals=[int(sample.get(key,0)) for sample in samples]
        summary[f"median_{key}"]=int(statistics.median(vals)) if vals else 0
        summary[f"max_{key}"]=int(max(vals)) if vals else 0
        summary[f"min_{key}"]=int(min(vals)) if vals else 0
    summary["total_bytes"]=int(total_bytes)
    summary["median_gpu_ms"]=summary["median_gpu_ns"]/1_000_000.0
    summary["median_cpu_ms"]=summary["median_cpu_ns"]/1_000_000.0
    summary["median_gpu_mib_per_s"]=(total_bytes/(1024.0*1024.0))/(summary["median_gpu_ns"]/1_000_000_000.0) if total_bytes > 0 and summary["median_gpu_ns"] > 0 else None
    summary["median_cpu_mib_per_s"]=(total_bytes/(1024.0*1024.0))/(summary["median_cpu_ns"]/1_000_000_000.0) if total_bytes > 0 and summary["median_cpu_ns"] > 0 else None
    summary["max_working_set_mib"]=summary["max_memory_working_set_bytes"]/(1024.0*1024.0)
    summary["max_device_allocated_mib"]=summary["max_memory_device_allocated_bytes"]/(1024.0*1024.0)
    return summary

def summarize_route(name,workload,samples):
    summary=summarize(name,workload,samples)
    route_counts={}
    for sample in samples:
        route=str(sample.get("route_kind","unknown"))
        route_counts[route]=route_counts.get(route,0)+1
    summary["route_kind_counts"]=route_counts
    return summary

rows=[]
fixture_1kb=pathlib.Path("bench/fixtures/english-1kb.txt").read_bytes()
fixture_1mb=pathlib.Path("bench/fixtures/english-1mb.txt").read_bytes()
normal_stream=bytes(ch for ch in fixture_1mb if (65 <= ch <= 90) or (97 <= ch <= 122))
if len(normal_stream) == 0:
    normal_stream=b"TheQuickBrownFoxJumpsOverTheLazyDog"
try:
    route_input_bytes=int(route_bytes_raw) if route_bytes_raw else len(fixture_1mb)
except ValueError:
    route_input_bytes=len(fixture_1mb)
route_input_bytes=max(4096, min(len(fixture_1mb), route_input_bytes))

def build_route_text(size):
    if route_text_kind == "normal-text":
        repeats=max(1,(size+len(normal_stream)-1)//len(normal_stream))
        payload=(normal_stream*repeats)[:size]
        return payload.decode("ascii","ignore")
    return "a"*size

# UTF-8 byte encode workload
samples=[]
for _ in range(runs):
    out=bridge.encode_utf8_bytes(fixture_1mb)
    if out is None:
        raise RuntimeError("metal encode_utf8_bytes failed")
    profile=_gpu.profile_last() or {}
    samples.append({
        "gpu_ns":int(profile.get("encode_gpu_ns",0)),
        "cpu_ns":int(profile.get("encode_cpu_ns",0)),
        "memory_active_bytes":int(profile.get("memory_active_bytes",0)),
        "memory_working_set_bytes":int(profile.get("memory_working_set_bytes",0)),
        "memory_device_allocated_bytes":int(profile.get("memory_device_allocated_bytes",0)),
        "memory_device_recommended_working_set_bytes":int(profile.get("memory_device_recommended_working_set_bytes",0)),
    })
rows.append(summarize(
    "metal-encode-utf8-bytes-1mb",
    {"input_bytes":len(fixture_1mb),"kind":"encode_utf8_bytes"},
    samples,
))

# Batch count workload
batch=[fixture_1kb]*4096
samples=[]
for _ in range(runs):
    out=bridge.count_nonzero_bytes_batch(batch)
    if out is None:
        raise RuntimeError("metal count_nonzero_bytes_batch failed")
    profile=_gpu.profile_last() or {}
    samples.append({
        "gpu_ns":int(profile.get("count_gpu_ns",0)),
        "cpu_ns":int(profile.get("count_cpu_ns",0)),
        "memory_active_bytes":int(profile.get("memory_active_bytes",0)),
        "memory_working_set_bytes":int(profile.get("memory_working_set_bytes",0)),
        "memory_device_allocated_bytes":int(profile.get("memory_device_allocated_bytes",0)),
        "memory_device_recommended_working_set_bytes":int(profile.get("memory_device_recommended_working_set_bytes",0)),
    })
rows.append(summarize(
    "metal-count-nonzero-batch-4096x1kb",
    {"segment_bytes":len(fixture_1kb),"batch":4096,"total_bytes":len(fixture_1kb)*4096,"kind":"count_nonzero_bytes_batch"},
    samples,
))

# Direct Metal BPE kernel workload (if rank payload initialization succeeds)
bpe_status={"ready":False,"reason":None}
try:
    enc=get_encoding("o200k_base")
    enc.load_mergeable_ranks()
    rank_payload=enc._ensure_rank_payload()
    if rank_payload and _gpu._ensure_metal_bpe_rank_table(rank_payload):
        bpe_status["ready"]=True
    else:
        bpe_status["reason"]="failed to initialize metal rank table"
except Exception as exc:
    bpe_status["reason"]=str(exc)

if bpe_status["ready"]:
    route_text=build_route_text(route_input_bytes)
    route_text_bytes=route_text.encode("utf-8")
    enc=get_encoding("o200k_base")

    # Route-level BPE workload through Python encode_gpu(device="metal"):
    # this captures direct-on-GPU vs stitched fallback behavior under env flags.
    samples=[]
    prev_force=os.environ.get("TURBOTOKEN_METAL_FORCE_ALL_PIECES")
    os.environ["TURBOTOKEN_METAL_FORCE_ALL_PIECES"]="1"
    try:
        for _ in range(runs):
            out=enc.encode_gpu(
                [route_text],
                device='metal',
                chunk_bytes=65536,
                overlap_bytes=256,
                strict_verify=False,
            )
            if not out:
                raise RuntimeError("metal encode_gpu route failed")
            profile=_gpu.profile_last() or {}
            bpe_gpu=int(profile.get("bpe_gpu_ns",0))
            bpe_cpu=int(profile.get("bpe_cpu_ns",0))
            stitch_gpu=int(profile.get("stitch_gpu_ns",0))
            stitch_cpu=int(profile.get("stitch_cpu_ns",0))
            route_kind="unknown"
            gpu_ns=bpe_gpu
            cpu_ns=bpe_cpu
            if bpe_gpu > 0 or int(profile.get("bpe_rounds",0)) > 0:
                route_kind="direct"
            elif stitch_gpu > 0 or int(profile.get("stitch_tokens",0)) > 0:
                route_kind="stitched"
                gpu_ns=stitch_gpu
                cpu_ns=stitch_cpu
            samples.append({
                "gpu_ns":gpu_ns,
                "cpu_ns":cpu_ns,
                "bpe_rounds":int(profile.get("bpe_rounds",0)),
                "bpe_submits":int(profile.get("bpe_submits",0)),
                "memory_active_bytes":int(profile.get("memory_active_bytes",0)),
                "memory_working_set_bytes":int(profile.get("memory_working_set_bytes",0)),
                "memory_device_allocated_bytes":int(profile.get("memory_device_allocated_bytes",0)),
                "memory_device_recommended_working_set_bytes":int(profile.get("memory_device_recommended_working_set_bytes",0)),
                "route_kind":route_kind,
            })
    finally:
        if prev_force is None:
            os.environ.pop("TURBOTOKEN_METAL_FORCE_ALL_PIECES", None)
        else:
            os.environ["TURBOTOKEN_METAL_FORCE_ALL_PIECES"]=prev_force
    rows.append(summarize_route(
        "metal-bpe-route-encode-gpu",
        {
            "input_bytes":len(route_text_bytes),
            "kind":"encode_gpu(device=metal)",
            "text_kind":route_text_kind,
            "env_direct_enable":str(_gpu._metal_bpe_direct_enabled()),
        },
        samples,
    ))

    if not skip_direct_kernel:
        # Direct bridge kernel workload for lower-bound device throughput.
        native_direct_tokens=None
        try:
            fixture_1mb_text=fixture_1mb.decode("utf-8")
            native_direct_tokens=enc.encode_ordinary(fixture_1mb_text)
        except Exception:
            native_direct_tokens=None
        samples=[]
        for _ in range(runs):
            out=bridge.encode_bpe_from_bytes(fixture_1mb)
            if out is None:
                raise RuntimeError("metal encode_bpe_from_bytes failed")
            profile=_gpu.profile_last() or {}
            matches_native=None
            if native_direct_tokens is not None:
                matches_native=(out == native_direct_tokens)
            samples.append({
                "gpu_ns":int(profile.get("bpe_gpu_ns",0)),
                "cpu_ns":int(profile.get("bpe_cpu_ns",0)),
                "bpe_rounds":int(profile.get("bpe_rounds",0)),
                "bpe_submits":int(profile.get("bpe_submits",0)),
                "memory_active_bytes":int(profile.get("memory_active_bytes",0)),
                "memory_working_set_bytes":int(profile.get("memory_working_set_bytes",0)),
                "memory_device_allocated_bytes":int(profile.get("memory_device_allocated_bytes",0)),
                "memory_device_recommended_working_set_bytes":int(profile.get("memory_device_recommended_working_set_bytes",0)),
                "matches_native":matches_native,
            })
        direct_summary=summarize(
            "metal-bpe-direct-encode-1mb",
            {"input_bytes":len(fixture_1mb),"kind":"encode_bpe_from_bytes"},
            samples,
        )
        if native_direct_tokens is not None:
            direct_summary["matches_native"]=all(sample.get("matches_native") is True for sample in samples)
            direct_summary["native_parity_failures"]=sum(
                1 for sample in samples if sample.get("matches_native") is False
            )
        else:
            direct_summary["matches_native"]=None
            direct_summary["native_parity_failures"]=None
        rows.append(direct_summary)

print(json.dumps({
    "tool":"gpu-memory-bench",
    "generated_at":time.time(),
    "runs_per_workload":runs,
    "probe":_gpu.backend_info(),
    "bpe_status":bpe_status,
    "rows":rows,
    "env":{
        "TURBOTOKEN_METAL_BPE_DIRECT_ENABLE":os.environ.get("TURBOTOKEN_METAL_BPE_DIRECT_ENABLE"),
        "TURBOTOKEN_METAL_BPE_DIRECT_MIN_BYTES":os.environ.get("TURBOTOKEN_METAL_BPE_DIRECT_MIN_BYTES"),
        "TURBOTOKEN_METAL_BPE_DIRECT_MAX_BYTES":os.environ.get("TURBOTOKEN_METAL_BPE_DIRECT_MAX_BYTES"),
        "TURBOTOKEN_GPU_MEMORY_SKIP_DIRECT_KERNEL":os.environ.get("TURBOTOKEN_GPU_MEMORY_SKIP_DIRECT_KERNEL"),
        "TURBOTOKEN_GPU_MEMORY_ROUTE_BYTES":os.environ.get("TURBOTOKEN_GPU_MEMORY_ROUTE_BYTES"),
        "TURBOTOKEN_GPU_MEMORY_ROUTE_TEXT_KIND":route_text_kind,
    },
    "note":"GPU memory rows are derived from Metal bridge telemetry: active bytes (last op), bridge working-set bytes (persistent MTLBuffer capacity), and device currentAllocatedSize when reported by the driver. Throughput columns use median GPU/CPU ns and known workload byte totals.",
}))
`;

const runResult = Bun.spawnSync({
  cmd: [python, "-c", py, String(runs)],
  cwd: resolvePath(),
  stdout: "pipe",
  stderr: "pipe",
});

if (runResult.exitCode !== 0) {
  writeJson(outputPath, {
    tool: "gpu-memory-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "failed",
    probe,
    stderr: new TextDecoder().decode(runResult.stderr).trim(),
  });
  console.log(`GPU memory benchmark failed; wrote failure record: ${outputPath}`);
  process.exit(1);
}

const runStdout = new TextDecoder().decode(runResult.stdout).trim();
let payload: Record<string, unknown>;
try {
  payload = JSON.parse(runStdout) as Record<string, unknown>;
} catch {
  writeJson(outputPath, {
    tool: "gpu-memory-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "failed",
    reason: "runner returned invalid JSON",
    raw: runStdout,
  });
  console.log(`GPU memory benchmark returned invalid JSON; wrote failure record: ${outputPath}`);
  process.exit(1);
}

writeJson(outputPath, {
  ...payload,
  speedProfile,
});
console.log(`Wrote GPU memory benchmark: ${outputPath}`);
