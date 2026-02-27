#!/usr/bin/env bun
import { ensureFixtures } from "./_fixtures";
import { commandExists, pythonExecutable, resolvePath, section, writeJson } from "./_lib";

section("CUDA GPU memory benchmark");
ensureFixtures();

const python = pythonExecutable();
const runsRaw = process.env.TURBOTOKEN_GPU_MEMORY_CUDA_RUNS?.trim();
const runs = runsRaw ? Math.max(1, Number.parseInt(runsRaw, 10) || 5) : 5;
const outputPath = resolvePath("bench", "results", `bench-gpu-memory-cuda-${Date.now()}.json`);

if (!commandExists("nvidia-smi")) {
  writeJson(outputPath, {
    tool: "gpu-memory-cuda-bench",
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: "nvidia-smi not found on PATH",
  });
  console.log(`CUDA memory benchmark skipped (missing nvidia-smi): ${outputPath}`);
  process.exit(0);
}

const py = `
import json
import os
import pathlib
import statistics
import subprocess
import sys
import time

runs=int(sys.argv[1])
pid=os.getpid()

def query_gpus():
    out=subprocess.check_output([
        "nvidia-smi",
        "--query-gpu=index,name,memory.total,memory.used",
        "--format=csv,noheader,nounits",
    ], text=True)
    rows=[]
    for line in out.splitlines():
        line=line.strip()
        if not line:
            continue
        parts=[p.strip() for p in line.split(",")]
        if len(parts) < 4:
            continue
        try:
            rows.append({
                "index": int(parts[0]),
                "name": parts[1],
                "memory_total_mib": int(parts[2]),
                "memory_used_mib": int(parts[3]),
            })
        except Exception:
            continue
    return rows

def query_pid_used_mib(proc_pid):
    try:
        out=subprocess.check_output([
            "nvidia-smi",
            "--query-compute-apps=pid,used_memory",
            "--format=csv,noheader,nounits",
        ], text=True)
    except Exception:
        return 0
    total=0
    for line in out.splitlines():
        line=line.strip()
        if not line:
            continue
        parts=[p.strip() for p in line.split(",")]
        if len(parts) < 2:
            continue
        if parts[0] != str(proc_pid):
            continue
        try:
            total += int(parts[1])
        except Exception:
            continue
    return total

def summarize(name, workload, samples):
    keys=[
        "elapsed_ns",
        "pid_used_mib_before",
        "pid_used_mib_after",
        "pid_used_mib_peak",
        "backend_allocated_bytes",
        "backend_reserved_bytes",
        "backend_peak_allocated_bytes",
    ]
    row={"name":name,"workload":workload,"runs":len(samples),"samples":samples}
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
        row[f"median_{key}"]=int(statistics.median(vals)) if vals else 0
        row[f"max_{key}"]=int(max(vals)) if vals else 0
        row[f"min_{key}"]=int(min(vals)) if vals else 0
    row["total_bytes"]=int(total_bytes)
    row["median_elapsed_ms"]=row["median_elapsed_ns"]/1_000_000.0
    row["median_mib_per_s"]=(total_bytes/(1024.0*1024.0))/(row["median_elapsed_ns"]/1_000_000_000.0) if total_bytes > 0 and row["median_elapsed_ns"] > 0 else None
    row["median_backend_peak_allocated_mib"]=row["median_backend_peak_allocated_bytes"]/(1024.0*1024.0)
    row["max_backend_peak_allocated_mib"]=row["max_backend_peak_allocated_bytes"]/(1024.0*1024.0)
    return row

gpus=query_gpus()
if not gpus:
    print(json.dumps({
        "tool":"gpu-memory-cuda-bench",
        "generated_at":time.time(),
        "status":"skipped",
        "reason":"nvidia-smi reports no visible CUDA GPUs",
    }))
    raise SystemExit(0)

backend=None
cp=None
torch=None
try:
    import cupy as _cp
    cp=_cp
    backend="cupy"
except Exception:
    cp=None

if backend is None:
    try:
        import torch as _torch
        if _torch.cuda.is_available():
            torch=_torch
            backend="torch"
    except Exception:
        torch=None

if backend is None:
    print(json.dumps({
        "tool":"gpu-memory-cuda-bench",
        "generated_at":time.time(),
        "status":"skipped",
        "reason":"Neither cupy nor torch.cuda is available",
        "gpus":gpus,
    }))
    raise SystemExit(0)

fixture_1kb=pathlib.Path("bench/fixtures/english-1kb.txt").read_bytes()
fixture_1mb=pathlib.Path("bench/fixtures/english-1mb.txt").read_bytes()

def run_cupy_encode():
    arr=cp.frombuffer(fixture_1mb, dtype=cp.uint8)
    out=arr.astype(cp.uint32)
    cp.cuda.Stream.null.synchronize()
    return [arr, out]

def run_cupy_count():
    chunk=cp.frombuffer(fixture_1kb, dtype=cp.uint8)
    batch=cp.tile(chunk[None, :], (4096, 1))
    counts=cp.count_nonzero(batch, axis=1)
    cp.cuda.Stream.null.synchronize()
    return [chunk, batch, counts]

def cupy_mem_stats():
    pool=cp.get_default_memory_pool()
    used=int(pool.used_bytes())
    reserved=int(pool.total_bytes())
    peak=max(used, reserved)
    return used, reserved, peak

def cupy_cleanup(refs):
    del refs
    cp.get_default_memory_pool().free_all_blocks()
    cp.cuda.Stream.null.synchronize()

def run_torch_encode():
    arr=torch.tensor(bytearray(fixture_1mb), dtype=torch.uint8, device="cuda")
    out=arr.to(dtype=torch.int32)
    torch.cuda.synchronize()
    return [arr, out]

def run_torch_count():
    chunk=torch.tensor(bytearray(fixture_1kb), dtype=torch.uint8, device="cuda")
    batch=chunk.repeat((4096, 1))
    counts=(batch != 0).sum(dim=1)
    torch.cuda.synchronize()
    return [chunk, batch, counts]

def torch_mem_stats():
    used=int(torch.cuda.memory_allocated())
    reserved=int(torch.cuda.memory_reserved())
    peak=int(torch.cuda.max_memory_allocated())
    return used, reserved, peak

def torch_cleanup(refs):
    del refs
    torch.cuda.empty_cache()
    torch.cuda.synchronize()

def collect_samples(run_fn, mem_stats_fn, cleanup_fn):
    samples=[]
    for _ in range(runs):
        if backend == "torch":
            torch.cuda.reset_peak_memory_stats()
        before=query_pid_used_mib(pid)
        started=time.perf_counter_ns()
        refs=run_fn()
        elapsed_ns=max(0, time.perf_counter_ns()-started)
        after=query_pid_used_mib(pid)
        alloc,reserved,peak=mem_stats_fn()
        samples.append({
            "elapsed_ns": int(elapsed_ns),
            "pid_used_mib_before": before,
            "pid_used_mib_after": after,
            "pid_used_mib_peak": max(before, after),
            "backend_allocated_bytes": alloc,
            "backend_reserved_bytes": reserved,
            "backend_peak_allocated_bytes": peak,
        })
        cleanup_fn(refs)
    return samples

if backend == "cupy":
    rows=[
        summarize(
            "cuda-cupy-encode-u8-to-u32-1mb",
            {"input_bytes": len(fixture_1mb), "kind": "encode_u8_to_u32"},
            collect_samples(run_cupy_encode, cupy_mem_stats, cupy_cleanup),
        ),
        summarize(
            "cuda-cupy-count-nonzero-batch-4096x1kb",
            {"segment_bytes": len(fixture_1kb), "batch": 4096, "total_bytes": len(fixture_1kb) * 4096, "kind": "count_nonzero_batch"},
            collect_samples(run_cupy_count, cupy_mem_stats, cupy_cleanup),
        ),
    ]
else:
    rows=[
        summarize(
            "cuda-torch-encode-u8-to-i32-1mb",
            {"input_bytes": len(fixture_1mb), "kind": "encode_u8_to_i32"},
            collect_samples(run_torch_encode, torch_mem_stats, torch_cleanup),
        ),
        summarize(
            "cuda-torch-count-nonzero-batch-4096x1kb",
            {"segment_bytes": len(fixture_1kb), "batch": 4096, "total_bytes": len(fixture_1kb) * 4096, "kind": "count_nonzero_batch"},
            collect_samples(run_torch_count, torch_mem_stats, torch_cleanup),
        ),
    ]

print(json.dumps({
    "tool":"gpu-memory-cuda-bench",
    "generated_at":time.time(),
    "status":"ok",
    "backend":backend,
    "runs_per_workload":runs,
    "pid":pid,
    "gpus":gpus,
    "rows":rows,
    "note":"CUDA memory rows include per-process used MiB from nvidia-smi query-compute-apps, backend allocator counters (cupy/torch), and median throughput derived from elapsed wall time over known workload bytes.",
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
    tool: "gpu-memory-cuda-bench",
    generatedAt: new Date().toISOString(),
    status: "failed",
    stderr: new TextDecoder().decode(runResult.stderr).trim(),
  });
  console.log(`CUDA memory benchmark failed; wrote failure record: ${outputPath}`);
  process.exit(1);
}

const runStdout = new TextDecoder().decode(runResult.stdout).trim();
let payload: Record<string, unknown>;
try {
  payload = JSON.parse(runStdout) as Record<string, unknown>;
} catch {
  writeJson(outputPath, {
    tool: "gpu-memory-cuda-bench",
    generatedAt: new Date().toISOString(),
    status: "failed",
    reason: "runner returned invalid JSON",
    raw: runStdout,
  });
  console.log(`CUDA memory benchmark returned invalid JSON; wrote failure record: ${outputPath}`);
  process.exit(1);
}

writeJson(outputPath, payload);
console.log(`Wrote CUDA GPU memory benchmark: ${outputPath}`);
