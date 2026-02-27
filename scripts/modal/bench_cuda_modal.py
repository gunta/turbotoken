#!/usr/bin/env python3
"""Run turbotoken benchmark suites on Modal NVIDIA GPUs.

Usage:
  modal run scripts/modal/bench_cuda_modal.py --runs 5

Optional environment:
  TURBOTOKEN_MODAL_GPU=L40S
  TURBOTOKEN_MODAL_PYTHON=3.11
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any

import modal

REPO_ROOT = Path(__file__).resolve().parents[2]
REMOTE_ROOT = Path("/root/turbotoken")
RESULTS_DIR = REMOTE_ROOT / "bench" / "results"


def _normalize_gpu_request(raw: str) -> str:
    token = raw.strip()
    if not token:
        return "L40S"
    aliases = {
        "RTX4090": "L40S",
        "RTX 4090": "L40S",
        "4090": "L40S",
    }
    return aliases.get(token.upper(), token)


GPU_REQUEST = _normalize_gpu_request(os.environ.get("TURBOTOKEN_MODAL_GPU", "L40S"))
PYTHON_VERSION = os.environ.get("TURBOTOKEN_MODAL_PYTHON", "3.11")

gpu_candidates: list[str] = []
for item in [GPU_REQUEST, "L40S", "A100", "H100"]:
    if item not in gpu_candidates:
        gpu_candidates.append(item)
GPU_SPEC: str | list[str] = gpu_candidates if len(gpu_candidates) > 1 else gpu_candidates[0]

image = (
    modal.Image.debian_slim(python_version=PYTHON_VERSION)
    .apt_install("curl", "git", "time", "hyperfine")
    .run_commands("curl -fsSL https://bun.sh/install | bash")
    .env(
        {
            "PATH": "/root/.bun/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        }
    )
    .pip_install("tiktoken", "rs-bpe", "regex", "cffi", "pytest", "hypothesis")
    .add_local_dir(str(REPO_ROOT), str(REMOTE_ROOT))
)

app = modal.App("turbotoken-bench-cuda")


def _tail(text: str, limit: int = 4000) -> str:
    if len(text) <= limit:
        return text
    return text[-limit:]


def _run(cmd: list[str], *, cwd: Path, env: dict[str, str]) -> dict[str, Any]:
    started = time.perf_counter()
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        text=True,
        capture_output=True,
    )
    elapsed_ms = (time.perf_counter() - started) * 1000.0
    return {
        "command": cmd,
        "exit_code": int(proc.returncode),
        "elapsed_ms": elapsed_ms,
        "stdout_tail": _tail(proc.stdout),
        "stderr_tail": _tail(proc.stderr),
    }


def _latest_result(prefix: str) -> Path | None:
    matches = sorted(RESULTS_DIR.glob(f"{prefix}*.json"), key=lambda p: p.stat().st_mtime)
    return matches[-1] if matches else None


def _read_json(path: Path | None) -> Any:
    if path is None or not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def _hyperfine_winner(payload: Any) -> dict[str, Any] | None:
    if not isinstance(payload, dict):
        return None
    rows = payload.get("results")
    if not isinstance(rows, list) or len(rows) == 0:
        return None
    valid_rows = [row for row in rows if isinstance(row, dict) and isinstance(row.get("mean"), (int, float))]
    if len(valid_rows) == 0:
        return None
    winner = min(valid_rows, key=lambda row: float(row["mean"]))
    return {
        "command": winner.get("command"),
        "mean_ms": float(winner["mean"]) * 1000.0,
    }


def _ram_row(payload: Any, name: str) -> dict[str, Any] | None:
    if not isinstance(payload, dict):
        return None
    rows = payload.get("rows")
    if not isinstance(rows, list):
        return None
    for row in rows:
        if isinstance(row, dict) and row.get("name") == name:
            kb = row.get("medianRssKb")
            if isinstance(kb, (int, float)):
                return {
                    "name": name,
                    "median_rss_mb": float(kb) / 1024.0,
                }
    return None


@app.function(image=image, gpu=GPU_SPEC, timeout=60 * 60, cpu=8, memory=32768)
def run_modal_gpu_benchmarks(runs: int = 5, long_mode: bool = False, include_training: bool = True) -> str:
    env = dict(os.environ)
    env["PYTHONPATH"] = f"{REMOTE_ROOT / 'python'}:{env.get('PYTHONPATH', '')}".rstrip(":")
    env["TURBOTOKEN_GPU_MEMORY_CUDA_RUNS"] = str(max(1, runs))
    env["TURBOTOKEN_RAM_RUNS"] = str(max(1, runs))
    env["TURBOTOKEN_BENCH_LONG"] = "1" if long_mode else "0"

    setup = [
        _run(["python3", "-m", "pip", "install", "-U", "pip"], cwd=REMOTE_ROOT, env=env),
        _run(["python3", "-m", "pip", "install", "-e", ".[dev]"], cwd=REMOTE_ROOT, env=env),
    ]

    benchmark_commands = [
        ["bun", "run", "scripts/bench-gpu-memory-cuda.ts"],
        ["bun", "run", "scripts/bench-startup.ts"],
        ["bun", "run", "scripts/bench-ram.ts"],
        ["bun", "run", "scripts/bench-competitors.ts"],
    ]
    if include_training:
        benchmark_commands.append(["bun", "run", "scripts/bench-training.ts"])

    runs_log = [_run(command, cwd=REMOTE_ROOT, env=env) for command in benchmark_commands]

    gpu_query = _run(
        [
            "nvidia-smi",
            "--query-gpu=index,name,memory.total,memory.used,driver_version",
            "--format=csv,noheader,nounits",
        ],
        cwd=REMOTE_ROOT,
        env=env,
    )
    gpu_brief = _run(["nvidia-smi"], cwd=REMOTE_ROOT, env=env)

    artifacts = {
        "gpu_memory_cuda": _latest_result("bench-gpu-memory-cuda-"),
        "startup_cold": _latest_result("bench-startup-cold-"),
        "startup_warm": _latest_result("bench-startup-warm-"),
        "ram": _latest_result("bench-ram-"),
        "competitors_encode": _latest_result("bench-competitors-python-encode-"),
        "competitors_decode": _latest_result("bench-competitors-python-decode-"),
        "competitors_count": _latest_result("bench-competitors-python-count-"),
        "training": _latest_result("bench-training-python-") if include_training else None,
    }

    artifact_payloads = {
        key: _read_json(path) for key, path in artifacts.items()
    }

    summary = {
        "startup_cold_winner": _hyperfine_winner(artifact_payloads["startup_cold"]),
        "startup_warm_winner": _hyperfine_winner(artifact_payloads["startup_warm"]),
        "competitors_encode_winner": _hyperfine_winner(artifact_payloads["competitors_encode"]),
        "competitors_decode_winner": _hyperfine_winner(artifact_payloads["competitors_decode"]),
        "competitors_count_winner": _hyperfine_winner(artifact_payloads["competitors_count"]),
        "training_winner": _hyperfine_winner(artifact_payloads["training"]),
        "ram_turbotoken": _ram_row(artifact_payloads["ram"], "python-ram-turbotoken-encode-1mb"),
        "ram_tiktoken": _ram_row(artifact_payloads["ram"], "python-ram-tiktoken-encode-1mb"),
        "ram_rs_bpe": _ram_row(artifact_payloads["ram"], "python-ram-rs-bpe-encode-1mb"),
        "ram_token_dagger": _ram_row(artifact_payloads["ram"], "python-ram-token-dagger-encode-1mb"),
    }

    payload = {
        "tool": "bench-modal-cuda",
        "generated_at": time.time(),
        "modal_gpu_request": GPU_REQUEST,
        "modal_gpu_spec": GPU_SPEC,
        "runs_per_workload": max(1, runs),
        "long_mode": bool(long_mode),
        "include_training": bool(include_training),
        "setup": setup,
        "commands": runs_log,
        "nvidia_smi_query": gpu_query["stdout_tail"],
        "nvidia_smi_raw_tail": gpu_brief["stdout_tail"],
        "artifact_paths": {key: str(path) if path is not None else None for key, path in artifacts.items()},
        "artifacts": artifact_payloads,
        "summary": summary,
        "note": "Runs existing repository benchmark scripts on Modal NVIDIA GPUs. Current codebase remains in scaffold/early implementation state per AGENTS.md.",
    }
    return json.dumps(payload)


@app.local_entrypoint()
def main(
    runs: int = 5,
    long_mode: bool = False,
    include_training: bool = True,
    output_path: str = "",
) -> None:
    payload_json = run_modal_gpu_benchmarks.remote(
        runs=max(1, runs),
        long_mode=bool(long_mode),
        include_training=bool(include_training),
    )

    if output_path.strip():
        out = Path(output_path)
    else:
        out = REPO_ROOT / "bench" / "results" / f"bench-modal-cuda-{int(time.time() * 1000)}.json"

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(payload_json, encoding="utf-8")
    print(f"Wrote Modal CUDA benchmark artifact: {out}")

