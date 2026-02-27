# Modal CUDA Benchmark Runner

This repository includes a Modal-based NVIDIA benchmark runner:

- `scripts/modal/bench_cuda_modal.py`

It runs existing benchmark scripts remotely and writes a local artifact JSON under `bench/results/`.

## Cost Control (Default Behavior)

Paid CUDA runs are now explicit opt-in.

- `bun run bench` does not include CUDA benchmarks by default.
- `modal run scripts/modal/bench_cuda_modal.py` now requires `--confirm-paid`.

Examples:

```bash
# local suite (no CUDA benchmark by default)
bun run bench

# local suite + CUDA rows (only if you explicitly want them)
bun run bench:cuda

# paid remote Modal run (explicit confirmation required)
bun run bench:modal:cuda
# or:
modal run scripts/modal/bench_cuda_modal.py --confirm-paid --runs 5
```

## What the Modal Runner Executes

Inside a Modal GPU container, it runs:

- `scripts/bench-gpu-memory-cuda.ts`
- `scripts/bench-startup.ts`
- `scripts/bench-ram.ts`
- `scripts/bench-competitors.ts`
- `scripts/bench-training.ts` (optional, enabled by default)

The output artifact includes:

- command logs (tail output, exit codes, elapsed ms)
- `nvidia-smi` probe output
- benchmark artifact paths and payloads
- summary winners (startup, competitors, training, RAM rows)

## Setup

1. Install Modal CLI + SDK (uv is recommended for faster Python tooling):

```bash
uv tool install modal
```

Fallback:

```bash
python3 -m pip install -U modal
```

2. Authenticate:

```bash
modal setup
```

3. Run:

```bash
modal run scripts/modal/bench_cuda_modal.py --confirm-paid --runs 5
```

## GPU Selection

Set `TURBOTOKEN_MODAL_GPU` before running:

```bash
TURBOTOKEN_MODAL_GPU=B200 modal run scripts/modal/bench_cuda_modal.py --confirm-paid --runs 5
```

Alias mapping in runner:

- `RTX4090`, `RTX 4090`, `4090` -> `L40S`

Current recommendation:

- Use `B200` for stable top-end comparisons.
- Use `B200+` for absolute headline numbers (Modal may route this to newer/faster Blackwell-class hardware; less apples-to-apples reproducibility).

## CUDA Image Choice (Current Best Default)

Default image in runner:

- `nvidia/cuda:13.1.1-cudnn-runtime-ubuntu24.04`

Rationale:

- Ubuntu 24.04 LTS base (modern toolchain/glibc)
- CUDA 13.1.1 generation (newer than previous 13.0.2 default)
- `runtime` flavor for smaller image and faster pull/start than `devel`
- `cudnn` variant keeps common DL runtime libs available

Override when needed:

```bash
TURBOTOKEN_MODAL_CUDA_IMAGE=nvidia/cuda:13.1.1-cudnn-devel-ubuntu24.04 \
  modal run scripts/modal/bench_cuda_modal.py --confirm-paid --runs 5
```

Use `devel` when you need full CUDA build toolchain (`nvcc`) inside the container.

## Python + Bun Install Strategy

Current runner strategy for speed:

- Python packages: `uv`-first install (`uv pip install --system ...`) with automatic `pip` fallback.
- Bun: direct download of prebuilt Bun binary from GitHub release ZIP (faster than running the shell installer script in this environment).

## Output

By default:

- `bench/results/bench-modal-cuda-<timestamp>.json`

Override path:

```bash
modal run scripts/modal/bench_cuda_modal.py --confirm-paid --runs 5 \
  --output-path bench/results/bench-modal-cuda-custom.json
```

## Latest Measured Run (February 27, 2026)

Command:

```bash
bun run bench:modal:cuda --runs 5
```

Top-level artifact:

- `bench/results/bench-modal-cuda-1772191604329.json`

Run metadata:

- GPU request/spec: `B200`
- Detected GPU (`nvidia-smi`): `NVIDIA B200` (`183359 MiB` total memory)
- CUDA image: `nvidia/cuda:13.1.1-cudnn-runtime-ubuntu24.04`
- Python: `3.12`
- Bun: `latest`
- GPU stack detected: `cupy=true`, `torch=false`

CUDA memory bench rows (from embedded `bench-gpu-memory-cuda` payload):

| Row | Median elapsed | Median throughput | Median backend peak alloc |
|---|---:|---:|---:|
| `cuda-cupy-encode-u8-to-u32-1mb` | `0.827 ms` | `1208.7 MiB/s` | `10 MiB` |
| `cuda-cupy-count-nonzero-batch-4096x1kb` | `0.674 ms` | `5934.6 MiB/s` | `9 MiB` |

Summary winners from the same Modal run:

- startup (cold): `python-startup-rs-bpe` (`84.28 ms`)
- startup (warm): `python-startup-rs-bpe` (`55.32 ms`)
- competitors encode: `python-encode-10kb-turbotoken` (`36.71 ms`)
- competitors decode: `python-decode-1000-tok-rs-bpe` (`79.42 ms`)
- competitors count: `python-count-100kb-turbotoken` (`40.69 ms`)
- training: `python-train-english-100kb-turbotoken-py-fallback-v320` (`47.96 ms`)

RAM medians from the same run:

- `python-ram-turbotoken-encode-1mb`: `50.54 MiB`
- `python-ram-tiktoken-encode-1mb`: `126.64 MiB`
- `python-ram-rs-bpe-encode-1mb`: `126.89 MiB`

Notes:

- `token-dagger` install failed in this run; its RAM row is absent in the summary.
- CUDA row samples include first-run CUDA initialization outliers; medians are the stable comparison value.

## References

- Modal CUDA guide: https://modal.com/docs/guide/cuda
- Modal GPU guide: https://modal.com/docs/guide/gpu
- Modal vLLM example: https://modal.com/docs/examples/vllm_inference
- Modal image API (`uv_pip_install`, registry images): https://modal.com/docs/reference/modal.Image
- NVIDIA CUDA container tags: https://hub.docker.com/r/nvidia/cuda/tags
