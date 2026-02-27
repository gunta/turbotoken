#!/usr/bin/env python3
"""Run turbotoken benchmark suites on Modal NVIDIA GPUs.

Usage:
  modal run scripts/modal/bench_cuda_modal.py --confirm-paid --runs 5

Optional environment:
  TURBOTOKEN_MODAL_GPU=B200
  TURBOTOKEN_MODAL_PYTHON=3.12
  TURBOTOKEN_MODAL_CUDA_IMAGE=nvidia/cuda:13.1.1-cudnn-runtime-ubuntu24.04
  TURBOTOKEN_MODAL_BUN_VERSION=latest
  TURBOTOKEN_MODAL_GPU_FALLBACKS=1
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any

import modal

def _resolve_local_repo_root() -> Path:
    explicit = os.environ.get("TURBOTOKEN_MODAL_LOCAL_REPO_ROOT", "").strip()
    if explicit:
        return Path(explicit).resolve()

    here = Path(__file__).resolve()
    if len(here.parents) >= 3:
        candidate = here.parents[2]
        if (candidate / "scripts").exists() and (candidate / "python").exists():
            return candidate

    cwd = Path.cwd().resolve()
    if (cwd / "scripts").exists() and (cwd / "python").exists():
        return cwd
    return cwd


REPO_ROOT = _resolve_local_repo_root()
REMOTE_ROOT = Path("/root/turbotoken")
RESULTS_DIR = REMOTE_ROOT / "bench" / "results"


def _normalize_gpu_request(raw: str) -> str:
    token = raw.strip()
    if not token:
        return "B200"
    aliases = {
        "RTX4090": "L40S",
        "RTX 4090": "L40S",
        "4090": "L40S",
        "H100": "H100!",
        "B200PLUS": "B200+",
    }
    return aliases.get(token.upper(), token)


GPU_REQUEST = _normalize_gpu_request(os.environ.get("TURBOTOKEN_MODAL_GPU", "B200"))
PYTHON_VERSION = os.environ.get("TURBOTOKEN_MODAL_PYTHON", "3.12")
CUDA_IMAGE = os.environ.get(
    "TURBOTOKEN_MODAL_CUDA_IMAGE", "nvidia/cuda:13.1.1-cudnn-runtime-ubuntu24.04"
)
BUN_VERSION = os.environ.get("TURBOTOKEN_MODAL_BUN_VERSION", "latest").strip() or "latest"
USE_GPU_FALLBACKS = os.environ.get("TURBOTOKEN_MODAL_GPU_FALLBACKS", "0").strip().lower() in {
    "1",
    "true",
    "yes",
    "on",
}

if USE_GPU_FALLBACKS:
    gpu_candidates: list[str] = []
    for item in [GPU_REQUEST, "B200", "H200", "H100!", "A100-80GB", "L40S"]:
        if item not in gpu_candidates:
            gpu_candidates.append(item)
    GPU_SPEC: str | list[str] = gpu_candidates if len(gpu_candidates) > 1 else gpu_candidates[0]
else:
    GPU_SPEC = GPU_REQUEST

image = (
    modal.Image.from_registry(CUDA_IMAGE, add_python=PYTHON_VERSION)
    .entrypoint([])
    .apt_install(
        "curl",
        "git",
        "unzip",
        "time",
        "hyperfine",
        "build-essential",
        "cmake",
        "ninja-build",
        "pkg-config",
        "libpcre2-dev",
    )
    .run_commands(
        (
            "set -eux; "
            "arch=$(uname -m); "
            "case \"$arch\" in "
            "x86_64) bun_arch=x64 ;; "
            "aarch64|arm64) bun_arch=aarch64 ;; "
            "*) echo \"Unsupported arch for Bun: $arch\"; exit 1 ;; "
            "esac; "
            f"bun_ver='{BUN_VERSION}'; "
            "if [ \"$bun_ver\" = \"latest\" ]; then "
            "bun_url=\"https://github.com/oven-sh/bun/releases/latest/download/bun-linux-${bun_arch}.zip\"; "
            "else "
            "bun_url=\"https://github.com/oven-sh/bun/releases/download/bun-v${bun_ver}/bun-linux-${bun_arch}.zip\"; "
            "fi; "
            "curl -fsSL \"$bun_url\" -o /tmp/bun.zip; "
            "unzip -q /tmp/bun.zip -d /tmp; "
            "install -m 0755 /tmp/bun-linux-${bun_arch}/bun /usr/local/bin/bun; "
            "rm -rf /tmp/bun.zip /tmp/bun-linux-${bun_arch}"
        )
    )
    .env(
        {
            "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        }
    )
    .uv_pip_install("uv", "tiktoken", "rs-bpe", "regex", "cffi", "pytest", "hypothesis")
    .add_local_dir(
        str(REPO_ROOT),
        str(REMOTE_ROOT),
        ignore=[
            ".git",
            ".git/**",
            "**/.git",
            "**/.git/**",
            ".venv/**",
            ".pytest_cache/**",
            ".zig-cache/**",
            "zig-out/**",
            "bench/results/**",
            "upstream/tiktoken/.git/**",
        ],
    )
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


def _module_available(module_name: str, *, cwd: Path, env: dict[str, str]) -> bool:
    probe = _run(
        [
            "python3",
            "-c",
            (
                "import importlib.util,sys;"
                f"sys.exit(0 if importlib.util.find_spec('{module_name}') else 1)"
            ),
        ],
        cwd=cwd,
        env=env,
    )
    return int(probe.get("exit_code", 1)) == 0


def _python_install(
    args: list[str],
    *,
    cwd: Path,
    env: dict[str, str],
    label: str,
) -> dict[str, Any]:
    uv_attempt = _run(["uv", "pip", "install", "--system", *args], cwd=cwd, env=env)
    uv_attempt["label"] = f"{label}-uv"
    if int(uv_attempt.get("exit_code", 1)) == 0:
        uv_attempt["installer"] = "uv"
        uv_attempt["label"] = label
        uv_attempt["attempts"] = [uv_attempt.copy()]
        return uv_attempt

    pip_attempt = _run(["python3", "-m", "pip", "install", *args], cwd=cwd, env=env)
    pip_attempt["label"] = f"{label}-pip"
    result = pip_attempt.copy()
    result["label"] = label
    result["installer"] = "pip" if int(pip_attempt.get("exit_code", 1)) == 0 else "failed"
    result["attempts"] = [uv_attempt, pip_attempt]
    return result


def _latest_result(prefix: str) -> Path | None:
    matches = sorted(
        [
            path
            for path in RESULTS_DIR.glob(f"{prefix}*.json")
            if not path.name.endswith(".meta.json")
        ],
        key=lambda p: p.stat().st_mtime,
    )
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
        _python_install(["-U", "pip", "setuptools", "wheel"], cwd=REMOTE_ROOT, env=env, label="bootstrap-packaging"),
        _python_install(["-e", ".[dev]"], cwd=REMOTE_ROOT, env=env, label="install-turbotoken-dev"),
    ]

    optional_installs: list[dict[str, Any]] = []

    minbpe_pip = _python_install(["minbpe"], cwd=REMOTE_ROOT, env=env, label="install-minbpe")
    optional_installs.append(minbpe_pip)
    if int(minbpe_pip.get("exit_code", 1)) != 0:
        _run(
            ["python3", "-c", "import shutil;shutil.rmtree('/tmp/minbpe', ignore_errors=True)"],
            cwd=REMOTE_ROOT,
            env=env,
        )
        minbpe_git = _run(
            ["git", "clone", "--depth", "1", "https://github.com/karpathy/minbpe.git", "/tmp/minbpe"],
            cwd=REMOTE_ROOT,
            env=env,
        )
        minbpe_git["label"] = "install-minbpe-git"
        optional_installs.append(minbpe_git)

    optional_installs.append(
        _python_install(["rustbpe"], cwd=REMOTE_ROOT, env=env, label="install-rustbpe")
    )
    token_dagger = _run(["bun", "run", "scripts/install-token-dagger.ts"], cwd=REMOTE_ROOT, env=env)
    token_dagger["label"] = "install-token-dagger"
    optional_installs.append(token_dagger)

    gpu_stack_attempts: list[dict[str, Any]] = []
    cupy_installed = _module_available("cupy", cwd=REMOTE_ROOT, env=env)
    torch_installed = _module_available("torch", cwd=REMOTE_ROOT, env=env)

    if not cupy_installed:
        for label, args in [
            ("install-cupy-cuda13x", ["cupy-cuda13x"]),
            ("install-cupy-cuda12x", ["cupy-cuda12x"]),
        ]:
            result = _python_install(args, cwd=REMOTE_ROOT, env=env, label=label)
            gpu_stack_attempts.append(result)
            cupy_installed = _module_available("cupy", cwd=REMOTE_ROOT, env=env)
            if cupy_installed:
                break

    if not cupy_installed and not torch_installed:
        for label, args in [
            ("install-torch-cu128", ["--index-url", "https://download.pytorch.org/whl/cu128", "torch"]),
            ("install-torch-cu126", ["--index-url", "https://download.pytorch.org/whl/cu126", "torch"]),
        ]:
            result = _python_install(args, cwd=REMOTE_ROOT, env=env, label=label)
            gpu_stack_attempts.append(result)
            torch_installed = _module_available("torch", cwd=REMOTE_ROOT, env=env)
            if torch_installed:
                break

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
        "python_version": PYTHON_VERSION,
        "cuda_image": CUDA_IMAGE,
        "bun_version": BUN_VERSION,
        "runs_per_workload": max(1, runs),
        "long_mode": bool(long_mode),
        "include_training": bool(include_training),
        "setup": setup,
        "optional_installs": optional_installs,
        "gpu_stack_attempts": gpu_stack_attempts,
        "gpu_stack_detected": {
            "cupy": cupy_installed,
            "torch": torch_installed,
        },
        "commands": runs_log,
        "nvidia_smi_query": gpu_query["stdout_tail"],
        "nvidia_smi_raw_tail": gpu_brief["stdout_tail"],
        "artifact_paths": {key: str(path) if path is not None else None for key, path in artifacts.items()},
        "artifacts": artifact_payloads,
        "summary": summary,
        "note": "Runs existing repository benchmark scripts on Modal NVIDIA GPUs with a CUDA container image. Current codebase remains in scaffold/early implementation state per AGENTS.md.",
    }
    return json.dumps(payload)


@app.local_entrypoint()
def main(
    runs: int = 5,
    long_mode: bool = False,
    include_training: bool = True,
    confirm_paid: bool = False,
    output_path: str = "",
) -> None:
    if not confirm_paid:
        raise SystemExit(
            "Refusing to start paid Modal CUDA benchmark without explicit confirmation. "
            "Re-run with --confirm-paid (or use `bun run bench:modal:cuda`)."
        )

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
