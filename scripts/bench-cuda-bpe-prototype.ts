#!/usr/bin/env bun
import { ensureFixtures } from "./_fixtures";
import { commandExists, pythonExecutable, resolvePath, section, writeJson } from "./_lib";

section("CUDA BPE prototype benchmark");
ensureFixtures();

const outputPath = resolvePath("bench", "results", `bench-cuda-bpe-prototype-${Date.now()}.json`);
const optIn = ["1", "true", "yes", "on"].includes(
  (process.env.TURBOTOKEN_CUDA_BPE_PROTOTYPE_ENABLE ?? "").trim().toLowerCase(),
);

if (!optIn) {
  writeJson(outputPath, {
    tool: "cuda-bpe-prototype",
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: "prototype is opt-in only; set TURBOTOKEN_CUDA_BPE_PROTOTYPE_ENABLE=1",
  });
  console.log(`CUDA BPE prototype skipped (opt-in disabled): ${outputPath}`);
  process.exit(0);
}

if (!commandExists("nvidia-smi")) {
  writeJson(outputPath, {
    tool: "cuda-bpe-prototype",
    generatedAt: new Date().toISOString(),
    status: "skipped",
    reason: "nvidia-smi not found on PATH",
  });
  console.log(`CUDA BPE prototype skipped (missing nvidia-smi): ${outputPath}`);
  process.exit(0);
}

const python = pythonExecutable();
const roundsCapRaw = (process.env.TURBOTOKEN_CUDA_BPE_PROTOTYPE_MAX_ROUNDS ?? "").trim();
const roundsCap = roundsCapRaw.length > 0 ? Math.max(1, Number.parseInt(roundsCapRaw, 10) || 1024) : 1024;
const payloadBytesRaw = (process.env.TURBOTOKEN_CUDA_BPE_PROTOTYPE_BYTES ?? "").trim();
const payloadBytes = payloadBytesRaw.length > 0 ? Math.max(1024, Number.parseInt(payloadBytesRaw, 10) || 262_144) : 262_144;

const py = `
import json
import time
import subprocess
import os

try:
    import cupy as cp
except Exception as exc:
    print(json.dumps({
        "tool":"cuda-bpe-prototype",
        "generated_at":time.time(),
        "status":"skipped",
        "reason":f"cupy unavailable: {exc}",
    }))
    raise SystemExit(0)

def query_gpu():
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
        rows.append({
            "index": int(parts[0]),
            "name": parts[1],
            "memory_total_mib": int(parts[2]),
            "memory_used_mib": int(parts[3]),
        })
    return rows

gpus=query_gpu()
if not gpus:
    print(json.dumps({
        "tool":"cuda-bpe-prototype",
        "generated_at":time.time(),
        "status":"skipped",
        "reason":"no visible CUDA GPUs",
    }))
    raise SystemExit(0)

# Toy rank table (sorted by rank asc) for prototype merge rounds:
# (a,a)->256, (256,256)->257, (257,257)->258
left_ids = cp.asarray([97, 256, 257], dtype=cp.uint32)
right_ids = cp.asarray([97, 256, 257], dtype=cp.uint32)
ranks = cp.asarray([1, 2, 3], dtype=cp.uint32)
merged_ids = cp.asarray([256, 257, 258], dtype=cp.uint32)
invalid = cp.uint32(0xFFFFFFFF)

payload_len = int(${payloadBytes})
max_rounds = int(${roundsCap})
payload = (b"a" * payload_len)
tokens = cp.frombuffer(payload, dtype=cp.uint8).astype(cp.uint32)

pool = cp.get_default_memory_pool()
pool.free_all_blocks()
cp.cuda.Stream.null.synchronize()

start_ns = time.perf_counter_ns()
rounds = 0
while rounds < max_rounds and int(tokens.size) > 1:
    rounds += 1

    left = tokens[:-1]
    right = tokens[1:]
    pair_rank = cp.full(left.shape, invalid, dtype=cp.uint32)
    pair_merge = cp.full(left.shape, invalid, dtype=cp.uint32)

    # Pair-rank lookup on GPU (vectorized cupy ops over candidate pairs).
    for idx in range(int(left_ids.size)):
        mask = (left == left_ids[idx]) & (right == right_ids[idx]) & (pair_rank == invalid)
        pair_rank = cp.where(mask, ranks[idx], pair_rank)
        pair_merge = cp.where(mask, merged_ids[idx], pair_merge)

    min_rank = int(cp.min(pair_rank).item())
    if min_rank == int(invalid):
        break

    merge_pos = pair_rank == cp.uint32(min_rank)
    if int(merge_pos.size) > 1:
        safe_prefix = cp.concatenate([cp.asarray([True], dtype=cp.bool_), cp.logical_not(merge_pos[:-1])])
        merge_pos = merge_pos & safe_prefix
    merge_count = int(cp.count_nonzero(merge_pos).item())
    if merge_count == 0:
        break

    # Iterative compaction stays on device.
    base = tokens.copy()
    base[:-1] = cp.where(merge_pos, pair_merge, base[:-1])
    keep = cp.ones(base.shape, dtype=cp.bool_)
    keep[1:] = cp.logical_not(merge_pos)
    write_idx = cp.cumsum(keep.astype(cp.int32)) - 1
    out_len = int(cp.sum(keep, dtype=cp.int32).item())
    compact = cp.empty((out_len,), dtype=cp.uint32)
    compact[write_idx[keep]] = base[keep]
    tokens = compact

cp.cuda.Stream.null.synchronize()
elapsed_ns = max(0, time.perf_counter_ns() - start_ns)

used = int(pool.used_bytes())
reserved = int(pool.total_bytes())
peak = max(used, reserved)
throughput_mib_s = (payload_len / (1024.0 * 1024.0)) / (elapsed_ns / 1_000_000_000.0) if elapsed_ns > 0 else None

print(json.dumps({
    "tool":"cuda-bpe-prototype",
    "generated_at":time.time(),
    "status":"ok",
    "gpus":gpus,
    "payload_bytes": payload_len,
    "max_rounds": max_rounds,
    "rounds_executed": rounds,
    "output_tokens": int(tokens.size),
    "elapsed_ns": int(elapsed_ns),
    "elapsed_ms": elapsed_ns / 1_000_000.0,
    "throughput_mib_per_s": throughput_mib_s,
    "backend_allocated_bytes": used,
    "backend_reserved_bytes": reserved,
    "backend_peak_allocated_bytes": peak,
    "note":"Prototype-only CUDA iterative BPE loop on toy rank table; opt-in and not wired into default CI/bench paths.",
}))
`;

const run = Bun.spawnSync({
  cmd: [python, "-c", py],
  cwd: resolvePath(),
  stdout: "pipe",
  stderr: "pipe",
});

const stdout = new TextDecoder().decode(run.stdout).trim();
const stderr = new TextDecoder().decode(run.stderr).trim();

if (run.exitCode !== 0) {
  writeJson(outputPath, {
    tool: "cuda-bpe-prototype",
    generatedAt: new Date().toISOString(),
    status: "failed",
    stderr,
    stdout,
  });
  console.log(`CUDA BPE prototype failed; wrote failure record: ${outputPath}`);
  process.exit(1);
}

try {
  const payload = JSON.parse(stdout) as Record<string, unknown>;
  writeJson(outputPath, payload);
  console.log(`Wrote CUDA BPE prototype benchmark: ${outputPath}`);
} catch {
  writeJson(outputPath, {
    tool: "cuda-bpe-prototype",
    generatedAt: new Date().toISOString(),
    status: "failed",
    reason: "prototype runner returned invalid JSON",
    raw: stdout,
    stderr,
  });
  console.log(`CUDA BPE prototype returned invalid JSON; wrote failure record: ${outputPath}`);
  process.exit(1);
}
