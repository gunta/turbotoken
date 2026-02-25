#!/usr/bin/env bun
import { pythonExecutable, resolvePath, runCommand, section, writeJson } from "./_lib";

const python = pythonExecutable();

section("Compatibility report");

const snippet = `
import importlib.util
import json
import sys

sys.path.insert(0, "python")
import turbotoken

if importlib.util.find_spec("tiktoken") is None:
    print(json.dumps({"status": "skipped", "reason": "tiktoken not installed"}))
    raise SystemExit(0)

import tiktoken

cases = [
    "",
    "hello world",
    "token counting for coding agents",
    "line one\\nline two",
    "emoji: 🚀✅",
    "日本語のテキスト",
]

report = {
    "status": "ok",
    "encodings": {},
}

for enc_name in turbotoken.list_encoding_names():
    enc_report = {
        "cases": [],
        "mismatch_count": 0,
    }

    try:
        tt = turbotoken.get_encoding(enc_name)
        tk = tiktoken.get_encoding(enc_name)
    except Exception as exc:
        enc_report["error"] = str(exc)
        report["encodings"][enc_name] = enc_report
        continue

    for text in cases:
        row = {
            "text": text,
            "text_repr": repr(text),
        }
        try:
            tt_tokens = tt.encode(text)
            tk_tokens = tk.encode(text)
            row["match"] = tt_tokens == tk_tokens
            row["turbotoken_tokens"] = tt_tokens
            row["tiktoken_tokens"] = tk_tokens
            if not row["match"]:
                enc_report["mismatch_count"] += 1
        except Exception as exc:
            row["error"] = str(exc)
            row["match"] = False
            enc_report["mismatch_count"] += 1

        enc_report["cases"].append(row)

    report["encodings"][enc_name] = enc_report

print(json.dumps(report))
`;

const run = runCommand(python, ["-c", snippet], { allowFailure: true });
if (run.code !== 0) {
  console.error(run.stderr.trim());
  process.exit(run.code);
}

const payload = JSON.parse(run.stdout.trim());
const output = resolvePath("bench", "results", `compat-report-${Date.now()}.json`);
writeJson(output, payload);

console.log(`Wrote compatibility report: ${output}`);
if (payload.status === "skipped") {
  console.warn(payload.reason);
}
