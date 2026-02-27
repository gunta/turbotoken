# Scorecard

Generated: 2026-02-27T16:29:04.277Z

## Comparison (100KB encode)
- turbotoken: 44.9 ms
- tiktoken: 216.5 ms
- speedup: 4.82x

## Startup ("hello" first encode)
- cold turbotoken: 65.2 ms
- cold tiktoken: 207.4 ms
- warm turbotoken: 63.6 ms
- warm tiktoken: 203.7 ms

## Winners
- encode 100KB: turbotoken
- encode 1MB: turbotoken
- count 1MB: turbotoken
- decode 128K tok: turbotoken
- training 100KB: turbotoken-python

## Artifacts
- startupCold: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-startup-cold-20260227-162101.json
- startupWarm: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-startup-warm-20260227-162132.json
- comparison: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-comparison-20260227-162050.json
- competitorsEncode: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-encode-20260227-162558.json
- competitorsDecode: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-decode-20260227-162719.json
- competitorsCount: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-count-20260227-162811.json
- training: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-training-python-20260227-145645.json
- ram: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-ram-1772204354545.json
- gpuMemory: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-memory-1772204436247.json

