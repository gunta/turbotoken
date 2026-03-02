from __future__ import annotations

import json

from turbotoken.cli import build_parser


def test_info_command_outputs_json(capsys) -> None:
    parser = build_parser()
    args = parser.parse_args(["info"])

    assert args.func(args) == 0

    out = capsys.readouterr().out.strip()
    payload = json.loads(out)
    assert payload["status"] == "scaffold"
    assert "encodings" in payload


def test_bench_command_outputs_metrics(capsys) -> None:
    parser = build_parser()
    args = parser.parse_args(["bench", "--iterations", "2", "--text", "hello"])

    assert args.func(args) == 0

    out = capsys.readouterr().out.strip()
    payload = json.loads(out)
    assert payload["iterations"] == 2
    assert payload["encoding"] == "o200k_base"
    assert payload["encode_total_ms"] >= 0
