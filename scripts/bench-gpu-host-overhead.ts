#!/usr/bin/env bun
import { ensureFixtures } from "./_fixtures";
import { acquireBenchmarkLock, benchSpeedProfile, pythonExecutable, resolvePath, section, writeJson } from "./_lib";

section("GPU host-overhead benchmark");
acquireBenchmarkLock({ label: "bench-gpu-host-overhead" });
ensureFixtures();

const python = pythonExecutable();
const speedProfile = benchSpeedProfile();
const fastMode = speedProfile === "fast";

const inputBytesRaw = (process.env.TURBOTOKEN_GPU_HOST_OVERHEAD_BYTES ?? "").trim();
const digestLoopsRaw = (process.env.TURBOTOKEN_GPU_HOST_OVERHEAD_DIGEST_LOOPS ?? "").trim();
const routeLoopsRaw = (process.env.TURBOTOKEN_GPU_HOST_OVERHEAD_ROUTE_LOOPS ?? "").trim();
const includeStressRaw = (process.env.TURBOTOKEN_GPU_HOST_OVERHEAD_INCLUDE_STRESS ?? "1").trim().toLowerCase();

const inputBytes = Number.isFinite(Number.parseInt(inputBytesRaw, 10))
  ? Math.max(4096, Number.parseInt(inputBytesRaw, 10))
  : (fastMode ? 262_144 : 1_048_576);
const digestLoops = Number.isFinite(Number.parseInt(digestLoopsRaw, 10))
  ? Math.max(16, Number.parseInt(digestLoopsRaw, 10))
  : (fastMode ? 256 : 4096);
const routeLoops = Number.isFinite(Number.parseInt(routeLoopsRaw, 10))
  ? Math.max(1, Number.parseInt(routeLoopsRaw, 10))
  : (fastMode ? 1 : 4);
const includeStress = includeStressRaw !== "0" && includeStressRaw !== "false" && includeStressRaw !== "no";

const outputPath = resolvePath("bench", "results", `bench-gpu-host-overhead-${Date.now()}.json`);

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
    tool: "gpu-host-overhead-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "skipped",
    reason: probeStderr || "failed to probe gpu backend",
  });
  console.log(`GPU host-overhead probe failed; wrote skip record: ${outputPath}`);
  process.exit(0);
}

let probe: Record<string, unknown>;
try {
  probe = JSON.parse(probeStdout) as Record<string, unknown>;
} catch {
  writeJson(outputPath, {
    tool: "gpu-host-overhead-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "skipped",
    reason: "invalid JSON from gpu backend probe",
    raw: probeStdout,
  });
  console.log(`GPU host-overhead probe returned invalid JSON; wrote skip record: ${outputPath}`);
  process.exit(0);
}

if (probe.available !== true) {
  writeJson(outputPath, {
    tool: "gpu-host-overhead-bench",
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
import hashlib,json,os,pathlib,statistics,sys,time
sys.path.insert(0,'python')
from turbotoken import _gpu,get_encoding

input_bytes=max(4096, int(sys.argv[1]))
digest_loops=max(16, int(sys.argv[2]))
route_loops=max(1, int(sys.argv[3]))
include_stress=bool(int(sys.argv[4]))

bridge=_gpu.get_metal_bridge()
if not bridge.available:
    print(json.dumps({
        "tool":"gpu-host-overhead-bench",
        "status":"skipped",
        "reason":bridge.error or "gpu bridge unavailable",
    }))
    raise SystemExit(0)

enc=get_encoding("o200k_base")
enc.load_mergeable_ranks()
rank_payload=enc._ensure_rank_payload()
if not rank_payload:
    print(json.dumps({
        "tool":"gpu-host-overhead-bench",
        "status":"failed",
        "reason":"missing rank payload",
    }))
    raise SystemExit(1)

def bench_mean_ms(fn, loops):
    start=time.perf_counter()
    for _ in range(loops):
        fn()
    return ((time.perf_counter()-start)*1000.0)/max(1,loops)

def mib_per_s(total_bytes, mean_ms):
    if mean_ms <= 0:
        return None
    return (total_bytes/(1024.0*1024.0))/(mean_ms/1000.0)

fixture_1mb=pathlib.Path("bench/fixtures/english-1mb.txt").read_bytes()
if len(fixture_1mb) == 0:
    fixture_1mb=b"The quick brown fox jumps over the lazy dog. "

normal_stream=bytes(ch for ch in fixture_1mb if (65 <= ch <= 90) or (97 <= ch <= 122))
if len(normal_stream) == 0:
    normal_stream=b"TheQuickBrownFoxJumpsOverTheLazyDog"
normal_stream_lower=bytes(((ch + 32) if (65 <= ch <= 90) else ch) for ch in normal_stream)


def build_text(kind):
    if kind == "low-entropy":
        return "a" * input_bytes
    source=normal_stream_lower
    repeats=max(1,(input_bytes+len(source)-1)//len(source))
    payload=(source*repeats)[:input_bytes]
    return payload.decode("ascii", "ignore")


def route_kind_from_profile(profile):
    bpe_gpu=int(profile.get("bpe_gpu_ns",0))
    stitch_gpu=int(profile.get("stitch_gpu_ns",0))
    bpe_rounds=int(profile.get("bpe_rounds",0))
    stitch_tokens=int(profile.get("stitch_tokens",0))
    if bpe_gpu > 0 or bpe_rounds > 0:
        return "direct"
    if stitch_gpu > 0 or stitch_tokens > 0:
        return "stitched"
    return "unknown"


def route_gpu_ms(profile, kind):
    bpe_gpu=float(int(profile.get("bpe_gpu_ns",0)))/1_000_000.0
    stitch_gpu=float(int(profile.get("stitch_gpu_ns",0)))/1_000_000.0
    if kind == "direct":
        return bpe_gpu
    if kind == "stitched":
        return stitch_gpu
    return max(bpe_gpu, stitch_gpu)


def route_cpu_ms(profile, kind):
    bpe_cpu=float(int(profile.get("bpe_cpu_ns",0)))/1_000_000.0
    stitch_cpu=float(int(profile.get("stitch_cpu_ns",0)))/1_000_000.0
    if kind == "direct":
        return bpe_cpu
    if kind == "stitched":
        return stitch_cpu
    return max(bpe_cpu, stitch_cpu)


def run_route(text_kind, enable_direct):
    text=build_text(text_kind)
    baseline=enc.encode(text)
    env_keys=(
        "TURBOTOKEN_METAL_FORCE_ALL_PIECES",
        "TURBOTOKEN_METAL_FORCE_ALL_PIECES_STRICT",
        "TURBOTOKEN_METAL_BPE_DIRECT_ENABLE",
        "TURBOTOKEN_METAL_BPE_DIRECT_MIN_BYTES",
        "TURBOTOKEN_METAL_BPE_DIRECT_MAX_BYTES",
        "TURBOTOKEN_METAL_BPE_DIRECT_LOW_ENTROPY_GUARD",
    )
    prev={key: os.environ.get(key) for key in env_keys}
    os.environ["TURBOTOKEN_METAL_FORCE_ALL_PIECES"]="1"
    os.environ["TURBOTOKEN_METAL_FORCE_ALL_PIECES_STRICT"]="0"
    os.environ["TURBOTOKEN_METAL_BPE_DIRECT_ENABLE"]="1" if enable_direct else "0"
    os.environ["TURBOTOKEN_METAL_BPE_DIRECT_MIN_BYTES"]=str(max(1, input_bytes // 2))
    os.environ["TURBOTOKEN_METAL_BPE_DIRECT_MAX_BYTES"]=str(max(input_bytes, input_bytes * 2))
    os.environ["TURBOTOKEN_METAL_BPE_DIRECT_LOW_ENTROPY_GUARD"]="1"

    wall_ms=[]
    gpu_ms=[]
    cpu_ms=[]
    host_overhead_ms=[]
    bpe_rounds=[]
    bpe_submits=[]
    route_kind_counts={}
    matches=True

    try:
        for _ in range(route_loops):
            started=time.perf_counter()
            out=enc.encode_gpu(
                [text],
                device='metal',
                chunk_bytes=65536,
                overlap_bytes=256,
                strict_verify=False,
            )
            elapsed_ms=(time.perf_counter()-started)*1000.0
            if not out:
                raise RuntimeError("encode_gpu(device='metal') returned empty output")
            tokens=out[0]
            if tokens != baseline:
                matches=False
            profile=_gpu.profile_last() or {}
            kind=route_kind_from_profile(profile)
            route_kind_counts[kind]=route_kind_counts.get(kind,0)+1
            run_gpu_ms=route_gpu_ms(profile, kind)
            run_cpu_ms=route_cpu_ms(profile, kind)
            wall_ms.append(elapsed_ms)
            gpu_ms.append(run_gpu_ms)
            cpu_ms.append(run_cpu_ms)
            host_overhead_ms.append(elapsed_ms - run_gpu_ms)
            bpe_rounds.append(int(profile.get("bpe_rounds",0)))
            bpe_submits.append(int(profile.get("bpe_submits",0)))
    finally:
        for key, value in prev.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key]=value

    mean_wall=statistics.mean(wall_ms)
    median_gpu=statistics.median(gpu_ms)
    median_cpu=statistics.median(cpu_ms)
    mean_host=statistics.mean(host_overhead_ms)
    return {
        "name":f"route-{text_kind}-direct-{'enabled' if enable_direct else 'disabled'}",
        "text_kind":text_kind,
        "direct_enabled":bool(enable_direct),
        "loops":route_loops,
        "input_bytes":input_bytes,
        "mean_wall_ms":mean_wall,
        "median_gpu_ms":median_gpu,
        "median_cpu_ms":median_cpu,
        "mean_host_overhead_ms":mean_host,
        "wall_mib_per_s":mib_per_s(input_bytes, mean_wall),
        "gpu_mib_per_s":mib_per_s(input_bytes, median_gpu) if median_gpu > 0 else None,
        "host_overhead_pct_of_wall":(mean_host/mean_wall*100.0) if mean_wall > 0 else None,
        "median_bpe_rounds":int(statistics.median(bpe_rounds)) if bpe_rounds else 0,
        "median_bpe_submits":int(statistics.median(bpe_submits)) if bpe_submits else 0,
        "route_kind_counts":route_kind_counts,
        "matches_baseline":matches,
    }

# Rank payload digest microbench (cached helper vs direct SHA256 each call)
_gpu._rank_payload_digest_short(rank_payload)
digest_cached_ms=bench_mean_ms(lambda: _gpu._rank_payload_digest_short(rank_payload), digest_loops)
digest_raw_ms=bench_mean_ms(lambda: hashlib.sha256(rank_payload).hexdigest()[:16], digest_loops)

rank_init_start=time.perf_counter()
rank_table_ready_cold=_gpu._ensure_metal_bpe_rank_table(rank_payload)
rank_table_cold_ms=(time.perf_counter()-rank_init_start)*1000.0
rank_init_start=time.perf_counter()
rank_table_ready_warm=_gpu._ensure_metal_bpe_rank_table(rank_payload)
rank_table_warm_ms=(time.perf_counter()-rank_init_start)*1000.0

rows=[]
rows.append(run_route("normal-text", False))
rows.append(run_route("normal-text", True))
if include_stress:
    rows.append(run_route("low-entropy", False))
    rows.append(run_route("low-entropy", True))

env_keys=[
    "TURBOTOKEN_METAL_THREADS_PER_GROUP_MULT",
    "TURBOTOKEN_METAL_ENCODE_THREADS_PER_GROUP_MULT",
    "TURBOTOKEN_METAL_COUNT_THREADS_PER_GROUP",
    "TURBOTOKEN_METAL_BPE_RESET_THREADS",
    "TURBOTOKEN_METAL_BPE_FIND_THREADS",
    "TURBOTOKEN_METAL_BPE_MARK_THREADS",
    "TURBOTOKEN_METAL_BPE_APPLY_THREADS",
    "TURBOTOKEN_METAL_BPE_COMPACT_THREADS",
    "TURBOTOKEN_METAL_BPE_EMIT_THREADS",
    "TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT",
    "TURBOTOKEN_METAL_BPE_ACTIVE_COMPACT_ENABLE",
    "TURBOTOKEN_METAL_BPE_ACTIVE_COMPACT_STRIDE",
]

print(json.dumps({
    "tool":"gpu-host-overhead-bench",
    "generated_at":time.time(),
    "speed_profile":"fast" if route_loops <= 1 else "full",
    "probe":_gpu.backend_info(),
    "config":{
        "input_bytes":input_bytes,
        "digest_loops":digest_loops,
        "route_loops":route_loops,
        "include_stress":include_stress,
    },
    "digest":{
        "cached_mean_ms":digest_cached_ms,
        "raw_mean_ms":digest_raw_ms,
        "cached_per_call_us":digest_cached_ms*1000.0,
        "raw_per_call_us":digest_raw_ms*1000.0,
        "speedup_raw_vs_cached":(digest_raw_ms/digest_cached_ms) if digest_cached_ms > 0 else None,
    },
    "rank_table_init":{
        "ready_cold":bool(rank_table_ready_cold),
        "ready_warm":bool(rank_table_ready_warm),
        "cold_ms":rank_table_cold_ms,
        "warm_ms":rank_table_warm_ms,
        "warm_vs_cold_ratio":(rank_table_warm_ms/rank_table_cold_ms) if rank_table_cold_ms > 0 else None,
    },
    "rows":rows,
    "env":{key: os.environ.get(key) for key in env_keys},
    "note":"Host-overhead microbench for Metal BPE route path. Compares cached digest helper vs raw hash, cold/warm rank-table setup, and wall-vs-GPU deltas for direct disabled/enabled on normal/stress text.",
}))
`;

const runResult = Bun.spawnSync({
  cmd: [python, "-c", py, String(inputBytes), String(digestLoops), String(routeLoops), includeStress ? "1" : "0"],
  cwd: resolvePath(),
  stdout: "pipe",
  stderr: "pipe",
});

const stdout = new TextDecoder().decode(runResult.stdout).trim();
const stderr = new TextDecoder().decode(runResult.stderr).trim();
if (runResult.exitCode !== 0) {
  writeJson(outputPath, {
    tool: "gpu-host-overhead-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "failed",
    reason: "python benchmark command failed",
    stderr,
  });
  console.error(stderr || `gpu host-overhead benchmark failed with exit code ${runResult.exitCode}`);
  process.exit(runResult.exitCode ?? 1);
}

let payload: Record<string, unknown>;
try {
  payload = JSON.parse(stdout) as Record<string, unknown>;
} catch {
  writeJson(outputPath, {
    tool: "gpu-host-overhead-bench",
    generatedAt: new Date().toISOString(),
    speedProfile,
    status: "failed",
    reason: "invalid JSON from python benchmark payload",
    raw: stdout,
    stderr,
  });
  console.error("gpu host-overhead benchmark produced invalid JSON payload");
  process.exit(1);
}

writeJson(outputPath, {
  ...payload,
  speedProfile,
  generatedAt: new Date().toISOString(),
});

const digest = (payload.digest ?? {}) as Record<string, unknown>;
const rows = Array.isArray(payload.rows) ? payload.rows : [];
console.log(`Wrote GPU host-overhead artifact: ${outputPath}`);
if (typeof digest.speedup_raw_vs_cached === "number" && Number.isFinite(digest.speedup_raw_vs_cached)) {
  console.log(`Digest cached speedup (raw/cached): ${Number(digest.speedup_raw_vs_cached).toFixed(2)}x`);
}
console.log(`Route rows captured: ${rows.length}`);
