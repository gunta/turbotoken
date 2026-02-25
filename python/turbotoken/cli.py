from __future__ import annotations

import argparse
import json
import platform
import sys
import time

from . import __version__
from . import _gpu
from ._native import get_native_bridge
from ._rank_files import rank_file_path
from .core import get_encoding, list_encoding_names


def _cmd_count(args: argparse.Namespace) -> int:
    enc = get_encoding(args.encoding)
    data = sys.stdin.read() if args.text == "-" else args.text
    print(enc.count(data))
    return 0


def _cmd_encode(args: argparse.Namespace) -> int:
    enc = get_encoding(args.encoding)
    data = sys.stdin.read() if args.text == "-" else args.text
    print(json.dumps(enc.encode(data)))
    return 0


def _cmd_decode(args: argparse.Namespace) -> int:
    enc = get_encoding(args.encoding)
    tokens = json.loads(args.tokens)
    print(enc.decode(tokens))
    return 0


def _cmd_info(_: argparse.Namespace) -> int:
    native = get_native_bridge()
    encodings = list_encoding_names()
    rank_files = {name: rank_file_path(name).exists() for name in encodings}
    gpu_info = _gpu.backend_info()
    payload = {
        "package_version": __version__,
        "python_version": platform.python_version(),
        "platform": platform.platform(),
        "encodings": encodings,
        "rank_files_cached": rank_files,
        "native_bridge": {
            "available": native.available,
            "version": native.version(),
            "error": native.error,
        },
        "gpu_backend_available": gpu_info["available"],
        "gpu_backend": gpu_info,
        "status": "scaffold",
        "note": "Python uses regex+BPE merge logic with cached .tiktoken ranks; native CPU acceleration is present, while Metal GPU is experimental byte-path acceleration (full GPU BPE is pending).",
    }
    print(json.dumps(payload, ensure_ascii=True))
    return 0


def _cmd_bench(args: argparse.Namespace) -> int:
    if args.iterations <= 0:
        raise SystemExit("--iterations must be > 0")

    enc = get_encoding(args.encoding)
    text = args.text

    encode_start = time.perf_counter()
    for _ in range(args.iterations):
        enc.encode(text)
    encode_s = time.perf_counter() - encode_start

    tokens = enc.encode(text)
    decode_start = time.perf_counter()
    for _ in range(args.iterations):
        enc.decode(tokens)
    decode_s = time.perf_counter() - decode_start

    count_start = time.perf_counter()
    for _ in range(args.iterations):
        enc.count(text)
    count_s = time.perf_counter() - count_start

    payload = {
        "encoding": args.encoding,
        "iterations": args.iterations,
        "text_bytes": len(text.encode("utf-8")),
        "encode_total_ms": round(encode_s * 1000.0, 3),
        "decode_total_ms": round(decode_s * 1000.0, 3),
        "count_total_ms": round(count_s * 1000.0, 3),
        "encode_ops_per_s": round(args.iterations / encode_s, 2) if encode_s > 0 else None,
        "decode_ops_per_s": round(args.iterations / decode_s, 2) if decode_s > 0 else None,
        "count_ops_per_s": round(args.iterations / count_s, 2) if count_s > 0 else None,
        "status": "python-bpe-benchmark",
    }
    print(json.dumps(payload, ensure_ascii=True))
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="turbotoken")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_count = sub.add_parser("count")
    p_count.add_argument("text")
    p_count.add_argument("--encoding", default="o200k_base")
    p_count.set_defaults(func=_cmd_count)

    p_encode = sub.add_parser("encode")
    p_encode.add_argument("text")
    p_encode.add_argument("--encoding", default="o200k_base")
    p_encode.set_defaults(func=_cmd_encode)

    p_decode = sub.add_parser("decode")
    p_decode.add_argument("tokens")
    p_decode.add_argument("--encoding", default="o200k_base")
    p_decode.set_defaults(func=_cmd_decode)

    p_info = sub.add_parser("info")
    p_info.set_defaults(func=_cmd_info)

    p_bench = sub.add_parser("bench")
    p_bench.add_argument("--encoding", default="o200k_base")
    p_bench.add_argument("--text", default="hello world")
    p_bench.add_argument("--iterations", type=int, default=1000)
    p_bench.set_defaults(func=_cmd_bench)

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
