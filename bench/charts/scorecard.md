# Scorecard

Generated: 2026-03-01T09:44:51.953Z

## Comparison (100KB encode)
- turbotoken: 42.9 ms
- tiktoken: 223.2 ms
- speedup: 5.21x

## Startup ("hello" first encode)
- cold turbotoken: 73.2 ms
- cold tiktoken: 216.7 ms
- cold gpt-tokenizer (Bun): 161.1 ms
- warm turbotoken: 67.5 ms
- warm tiktoken: 229 ms
- warm gpt-tokenizer (Bun): 182 ms

## WASM (Node + Browser)
- total wasm rows: 15
- node wasm rows: 6
- browser wasm rows: 3
- node row node-wasm-startup-first-encode-hello: 97.97 ms | throughput n/a
- node row node-wasm-startup-first-bpe-encode-hello: 158.16 ms | throughput n/a
- node row node-wasm-encode-utf8-bytes-100kb: 93.14 ms | 1.05 MB/s
- node row node-wasm-encode-utf8-bytes-1mb: 100.27 ms | 9.97 MB/s
- node row node-wasm-encode-bpe-o200k-100kb: 182.9 ms | 0.53 MB/s
- node row node-wasm-encode-bpe-o200k-1mb: 465.89 ms | 2.15 MB/s
- browser row browser-wasm-startup-first-encode-hello: not-run (browser benchmark harness is not configured in this local run)
- browser row browser-wasm-encode-utf8-bytes-1mb: not-run (browser benchmark harness is not configured in this local run)
- browser row browser-wasm-encode-bpe-o200k-1mb: not-run (browser benchmark harness is not configured in this local run)

## GPU Direct A/B (Headline: normal-text)
- profile count: 2
- headline profile: normal-text
- headline disabled: 3312.91 ms (0.075 MiB/s)
- headline enabled: 3330.36 ms (0.075 MiB/s)
- headline slowdown: 0.53%
- headline throughput ratio (enabled/disabled): 0.995x
- headline route disabled (GPU-only): 529.289 MiB/s
- headline route enabled (GPU-only): 457.527 MiB/s
- headline route throughput ratio (enabled/disabled): 0.864x
- stress profile: low-entropy
- stress slowdown: 1.66%
- stress throughput ratio (enabled/disabled): 0.984x

## Winners
- encode 100KB: turbotoken
- encode 1MB: n/a
- count 1MB: n/a
- decode 128K tok: n/a
- chat encode: turbotoken
- chat count: turbotoken
- chat limit: turbotoken
- training 100KB: turbotoken-native

## Artifacts
- startupCold: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-startup-cold-20260301-094122.json
- startupWarm: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-startup-warm-20260301-094133.json
- comparison: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-comparison-20260301-094157.json
- competitorsEncode: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-encode-20260301-094159.json
- competitorsDecode: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-decode-20260301-094211.json
- competitorsCount: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-count-20260301-094219.json
- chatHelpers: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-chat-helpers-20260301-094228.json
- training: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-training-python-20260301-094233.json
- ram: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-ram-1772358191018.json
- wasm: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-wasm-1772358193405.json
- gpuMemory: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-memory-1772351129407.json
- gpuOverlap: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-overlap-1772358286820.json
- gpuBpeDirect: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-bpe-direct-1772358225658.json

