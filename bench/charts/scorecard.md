# Scorecard

Generated: 2026-03-02T06:28:07.151Z

## Comparison (100KB encode)
- turbotoken: 41 ms
- tiktoken: 277.1 ms
- speedup: 6.75x

## Startup ("hello" first encode)
- cold turbotoken: 67.9 ms
- cold tiktoken: 219.4 ms
- cold gpt-tokenizer (Bun): 176.5 ms
- warm turbotoken: 69.4 ms
- warm tiktoken: 216 ms
- warm gpt-tokenizer (Bun): 174.6 ms

## WASM (Node + Browser)
- total wasm rows: 15
- node wasm rows: 6
- browser wasm rows: 3
- node row node-wasm-startup-first-encode-hello: 100.01 ms | throughput n/a
- node row node-wasm-startup-first-bpe-encode-hello: 149.24 ms | throughput n/a
- node row node-wasm-encode-utf8-bytes-100kb: 76.78 ms | 1.27 MB/s
- node row node-wasm-encode-utf8-bytes-1mb: 77.89 ms | 12.84 MB/s
- node row node-wasm-encode-bpe-o200k-100kb: 176.44 ms | 0.55 MB/s
- node row node-wasm-encode-bpe-o200k-1mb: 496.61 ms | 2.01 MB/s
- browser row browser-wasm-startup-first-encode-hello: not-run (browser benchmark harness is not configured in this local run)
- browser row browser-wasm-encode-utf8-bytes-1mb: not-run (browser benchmark harness is not configured in this local run)
- browser row browser-wasm-encode-bpe-o200k-1mb: not-run (browser benchmark harness is not configured in this local run)

## GPU Direct A/B (Headline: normal-text)
- profile count: 2
- headline profile: normal-text
- headline disabled: 0.67 ms (374.737 MiB/s)
- headline enabled: 0.71 ms (352.015 MiB/s)
- headline slowdown: 6.45%
- headline throughput ratio (enabled/disabled): 0.939x
- headline route disabled (GPU-only): n/a
- headline route enabled (GPU-only): n/a
- headline route throughput ratio (enabled/disabled): n/a
- stress profile: low-entropy
- stress slowdown: 5.07%
- stress throughput ratio (enabled/disabled): 0.952x

## Winners
- encode 100KB: turbotoken
- encode 1MB: turbotoken
- count 1MB: turbotoken
- decode 128K tok: n/a
- chat encode: turbotoken
- chat count: turbotoken
- chat limit: turbotoken
- training 100KB: turbotoken-native

## Artifacts
- startupCold: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-startup-cold-20260301-171136.json
- startupWarm: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-startup-warm-20260301-171146.json
- comparison: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-comparison-20260301-103552.json
- competitorsEncode: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-encode-20260301-171201.json
- competitorsDecode: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-decode-20260301-171212.json
- competitorsCount: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-count-20260301-171220.json
- chatHelpers: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-chat-helpers-20260301-103624.json
- training: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-training-python-20260302-044644.json
- ram: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-ram-1772385156527.json
- wasm: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-wasm-1772421489508.json
- gpuMemory: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-memory-1772432853486.json
- gpuOverlap: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-overlap-1772427133498.json
- gpuBpeDirect: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-bpe-direct-1772432813845.json

