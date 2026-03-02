from __future__ import annotations

import json

from turbotoken.cli import build_parser


def test_cli_bench_smoke(capsys) -> None:
    parser = build_parser()
    args = parser.parse_args(["bench", "--iterations", "3", "--text", "hello"])
    assert args.func(args) == 0

    payload = json.loads(capsys.readouterr().out.strip())
    assert payload["iterations"] == 3
    assert payload["status"] == "python-bpe-benchmark"
