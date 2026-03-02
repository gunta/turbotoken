from __future__ import annotations

import random
import os
from collections import Counter

from turbotoken import train_encoding_from_iterator, train_mergeable_ranks_from_iterator
from turbotoken._native import get_native_bridge
from turbotoken.training import _accumulate_chunks, _compile_pattern


def _counts_from_regex_module(pattern: str, corpus: list[str]) -> Counter[bytes]:
    try:
        import regex
    except ModuleNotFoundError:
        return Counter()

    expected: Counter[bytes] = Counter()
    compiled = regex.compile(pattern)
    for text in corpus:
        local = Counter(compiled.findall(text))
        local.pop("", None)
        for piece, count in local.items():
            expected[piece.encode("utf-8")] += count
    return expected


def test_train_mergeable_ranks_learns_common_pair() -> None:
    pat, ranks = train_mergeable_ranks_from_iterator(
        ["abababab"],
        vocab_size=257,
        pattern=r"[a-z]+",
        min_frequency=1,
    )
    assert pat == r"[a-z]+"
    assert ranks[b"ab"] == 256


def test_train_encoding_roundtrip() -> None:
    enc = train_encoding_from_iterator(
        ["abababab", "ababa"],
        vocab_size=258,
        name="toy",
        pattern=r"[a-z]+",
        min_frequency=1,
    )
    text = "ababab"
    tokens = enc.encode(text)
    assert any(token >= 256 for token in tokens)
    assert enc.decode(tokens) == text


def test_train_min_frequency_gate() -> None:
    _, ranks = train_mergeable_ranks_from_iterator(
        ["abc"],
        vocab_size=300,
        pattern=r"[a-z]+",
        min_frequency=5,
    )
    assert len(ranks) == 256


def test_ascii_o200k_native_pretokenize_matches_regex_counts() -> None:
    pattern, compiled = _compile_pattern(None)
    corpus = ["Tokenizer matters, for coding agents.\n", "we're in a scaffold-stage repository.\n"]

    expected = _counts_from_regex_module(pattern, corpus)
    if not expected:
        return
    actual = _accumulate_chunks(corpus, compiled, use_native_ascii_o200k=True)
    assert actual == expected


def test_ascii_o200k_native_pretokenize_fuzz_is_deterministic() -> None:
    _, compiled = _compile_pattern(None)
    rng = random.Random(0)
    alphabet = " abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789,.-/'\n\t"
    corpus = ["".join(rng.choice(alphabet) for _ in range(1024)) for _ in range(4)]

    first = _accumulate_chunks(corpus, compiled, use_native_ascii_o200k=True)
    second = _accumulate_chunks(corpus, compiled, use_native_ascii_o200k=True)
    assert first == second
    assert sum(first.values()) > 0


def test_default_ascii_fast_path_matches_regex_counts() -> None:
    pattern, compiled = _compile_pattern(None)
    corpus = [
        "Tokenizer matters, for coding agents.\n",
        "we're in a scaffold-stage repository.\n",
        "A MIX of UPPER and lower CASE plus 123 numbers.\n",
    ]

    expected = _counts_from_regex_module(pattern, corpus)
    if not expected:
        return
    actual = _accumulate_chunks(corpus, compiled, use_native_ascii_o200k=False)
    assert actual == expected


def test_default_pattern_non_ascii_matches_regex_counts() -> None:
    pattern, compiled = _compile_pattern(None)
    corpus = [
        "café naïve résumé\n",
        "γειά σου κόσμε — tokenizer\n",
    ]

    expected = _counts_from_regex_module(pattern, corpus)
    if not expected:
        return
    actual = _accumulate_chunks(corpus, compiled, use_native_ascii_o200k=False)
    assert actual == expected


def test_default_pattern_native_direct_matches_python() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        return

    text = "Tokenizer matters, for coding agents.\n" * 8

    prev_backend = os.environ.get("TURBOTOKEN_TRAINING_BACKEND")
    prev_disable = os.environ.get("TURBOTOKEN_NATIVE_TRAINING_DISABLE")
    prev_direct = os.environ.get("TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII")
    try:
        os.environ["TURBOTOKEN_TRAINING_BACKEND"] = "python"
        os.environ["TURBOTOKEN_NATIVE_TRAINING_DISABLE"] = "1"
        _, expected = train_mergeable_ranks_from_iterator(
            [text],
            vocab_size=320,
            pattern=None,
            min_frequency=2,
        )

        os.environ["TURBOTOKEN_TRAINING_BACKEND"] = "native"
        os.environ.pop("TURBOTOKEN_NATIVE_TRAINING_DISABLE", None)
        os.environ["TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII"] = "1"
        _, actual = train_mergeable_ranks_from_iterator(
            [text],
            vocab_size=320,
            pattern=None,
            min_frequency=2,
        )
    finally:
        if prev_backend is None:
            os.environ.pop("TURBOTOKEN_TRAINING_BACKEND", None)
        else:
            os.environ["TURBOTOKEN_TRAINING_BACKEND"] = prev_backend
        if prev_disable is None:
            os.environ.pop("TURBOTOKEN_NATIVE_TRAINING_DISABLE", None)
        else:
            os.environ["TURBOTOKEN_NATIVE_TRAINING_DISABLE"] = prev_disable
        if prev_direct is None:
            os.environ.pop("TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII", None)
        else:
            os.environ["TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII"] = prev_direct

    assert actual == expected


def test_default_pattern_native_direct_multi_matches_python() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        return

    corpus = [
        "Tokenizer matters, for coding agents.\n" * 4,
        "we're in a scaffold-stage repository.\n" * 4,
    ]

    prev_backend = os.environ.get("TURBOTOKEN_TRAINING_BACKEND")
    prev_disable = os.environ.get("TURBOTOKEN_NATIVE_TRAINING_DISABLE")
    prev_direct = os.environ.get("TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII")
    try:
        os.environ["TURBOTOKEN_TRAINING_BACKEND"] = "python"
        os.environ["TURBOTOKEN_NATIVE_TRAINING_DISABLE"] = "1"
        _, expected = train_mergeable_ranks_from_iterator(
            corpus,
            vocab_size=320,
            pattern=None,
            min_frequency=2,
        )

        os.environ["TURBOTOKEN_TRAINING_BACKEND"] = "native"
        os.environ.pop("TURBOTOKEN_NATIVE_TRAINING_DISABLE", None)
        os.environ["TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII"] = "1"
        _, actual = train_mergeable_ranks_from_iterator(
            corpus,
            vocab_size=320,
            pattern=None,
            min_frequency=2,
        )
    finally:
        if prev_backend is None:
            os.environ.pop("TURBOTOKEN_TRAINING_BACKEND", None)
        else:
            os.environ["TURBOTOKEN_TRAINING_BACKEND"] = prev_backend
        if prev_disable is None:
            os.environ.pop("TURBOTOKEN_NATIVE_TRAINING_DISABLE", None)
        else:
            os.environ["TURBOTOKEN_NATIVE_TRAINING_DISABLE"] = prev_disable
        if prev_direct is None:
            os.environ.pop("TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII", None)
        else:
            os.environ["TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII"] = prev_direct

    assert actual == expected
