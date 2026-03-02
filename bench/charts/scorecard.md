# Scorecard

Generated: 2026-03-02T11:48:37.461Z

## Comparison (100KB encode)
- turbotoken: 41 ms
- tiktoken: 277.1 ms
- speedup: 6.75x

## Startup ("hello" first encode)
- cold turbotoken: 67.5 ms
- cold tiktoken: 220.7 ms
- cold gpt-tokenizer (Bun): 170.6 ms
- warm turbotoken: 74.3 ms
- warm tiktoken: 228.2 ms
- warm gpt-tokenizer (Bun): 179.5 ms

## WASM (Node + Browser)
- total wasm rows: 15
- node wasm rows: 6
- browser wasm rows: 3
- node row node-wasm-startup-first-encode-hello: 88 ms | throughput n/a
- node row node-wasm-startup-first-bpe-encode-hello: 164.75 ms | throughput n/a
- node row node-wasm-encode-utf8-bytes-100kb: 86.02 ms | 1.14 MB/s
- node row node-wasm-encode-utf8-bytes-1mb: 92.93 ms | 10.76 MB/s
- node row node-wasm-encode-bpe-o200k-100kb: 178.12 ms | 0.55 MB/s
- node row node-wasm-encode-bpe-o200k-1mb: 500.62 ms | 2 MB/s
- browser row browser-wasm-startup-first-encode-hello: ok | 1.84 ms | throughput n/a
- browser row browser-wasm-encode-utf8-bytes-1mb: ok | 0.32 ms | 3125 MB/s
- browser row browser-wasm-encode-bpe-o200k-1mb: ok | 298.18 ms | 3.35 MB/s

## GPU Direct A/B (Headline: normal-text)
- profile count: 4
- headline profile: normal-text
- headline disabled: 0.71 ms (350.053 MiB/s)
- headline enabled: 0.7 ms (356.718 MiB/s)
- headline slowdown: -1.87%
- headline throughput ratio (enabled/disabled): 1.019x
- headline route disabled (GPU-only): n/a
- headline route enabled (GPU-only): n/a
- headline route throughput ratio (enabled/disabled): n/a
- stress profile: low-entropy
- stress slowdown: 1.38%
- stress throughput ratio (enabled/disabled): 0.986x
- long-lane headline key: normalTextLong
- long-lane bytes: 1,048,576
- long-lane disabled: 113.84 ms (8.784 MiB/s)
- long-lane enabled: 66.26 ms (15.091 MiB/s)
- long-lane slowdown: -41.79%
- long-lane throughput ratio (enabled/disabled): 1.718x
- long-lane route disabled (GPU-only): 35088.95 MiB/s
- long-lane route enabled (GPU-only): 36.583 MiB/s
- long-lane route throughput ratio (enabled/disabled): 0.001x
- long-lane stress key: lowEntropyLong
- long-lane stress slowdown: -4.85%
- long-lane stress throughput ratio (enabled/disabled): 1.051x

## Winners
- encode 100KB: turbotoken
- encode 1MB: turbotoken
- count 1MB: turbotoken
- decode 128K tok: n/a
- chat encode: turbotoken
- chat count: turbotoken
- chat limit: turbotoken
- training 100KB: turbotoken-native
- training 1MB native: turbotoken-native
- training 1MB native latency: 56.7 ms
- training 1MB native throughput: 17.635 MiB/s
- training 1MB native RSS: 18.68 MB

## Artifacts
- startupCold: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-startup-cold-20260302-113906.json
- startupWarm: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-startup-warm-20260302-113945.json
- comparison: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-comparison-20260301-103552.json
- competitorsEncode: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-encode-20260302-114054.json
- competitorsDecode: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-decode-20260301-171212.json
- competitorsCount: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-count-20260301-171220.json
- chatHelpers: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-chat-helpers-20260301-103624.json
- training: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-training-python-20260302-112550.json
- ram: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-ram-1772450936168.json
- wasm: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-wasm-1772450810515.json
- gpuMemory: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-memory-1772451219726.json
- gpuOverlap: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-overlap-1772451519356.json
- gpuBpeDirect: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-bpe-direct-1772451241564.json

