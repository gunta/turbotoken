# Modal CUDA Benchmark Runner

This repository now includes a Modal-based runner for NVIDIA GPU benchmark execution:

- `scripts/modal/bench_cuda_modal.py`

It runs existing benchmark scripts remotely and writes a local artifact JSON under `bench/results/`.

## What It Runs

Inside a Modal GPU container, the runner executes:

- `scripts/bench-gpu-memory-cuda.ts`
- `scripts/bench-startup.ts`
- `scripts/bench-ram.ts`
- `scripts/bench-competitors.ts`
- `scripts/bench-training.ts` (optional, enabled by default)

The output artifact includes:

- command logs (tail output, exit codes, elapsed ms)
- `nvidia-smi` probe output
- discovered benchmark artifact paths
- parsed artifact JSON payloads
- winner/summary rows for startup, competitors, training, and RAM rows

## Setup

1. Install Modal CLI and SDK:

```bash
python3 -m pip install -U modal
```

2. Authenticate:

```bash
modal setup
```

3. Run the Modal benchmark:

```bash
modal run scripts/modal/bench_cuda_modal.py --runs 5
```

or:

```bash
bun run bench:modal:cuda
```

## GPU Selection

Set target GPU with `TURBOTOKEN_MODAL_GPU` before running:

```bash
TURBOTOKEN_MODAL_GPU=L40S modal run scripts/modal/bench_cuda_modal.py --runs 5
```

The runner also accepts consumer aliases and maps them to datacenter equivalents:

- `RTX4090`, `RTX 4090`, `4090` -> `L40S`

Current Modal GPU docs list datacenter SKUs (for example `L40S`, `A100`, `H100`, `H200`, `B200`) rather than consumer `RTX 4090`.

## Output

By default, it writes:

- `bench/results/bench-modal-cuda-<timestamp>.json`

You can override this path:

```bash
modal run scripts/modal/bench_cuda_modal.py --runs 5 --output-path bench/results/bench-modal-cuda-custom.json
```

