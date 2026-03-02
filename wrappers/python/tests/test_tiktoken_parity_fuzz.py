from __future__ import annotations

import random

import pytest

from turbotoken import get_encoding, list_encoding_names

tiktoken = pytest.importorskip("tiktoken")

_ALPHABET = (
    "abcdefghijklmnopqrstuvwxyz"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789"
    " \n\t"
    "!@#$%^&*()[]{}<>?/\\|`~;:'\",.-_+="
    "日本語テキスト"
    "🚀✅🙂"
)


def _fuzz_cases(count: int = 64) -> list[str]:
    rng = random.Random(20260224)
    out: list[str] = []
    for _ in range(count):
        size = rng.randint(0, 120)
        out.append("".join(rng.choice(_ALPHABET) for _ in range(size)))
    return out


@pytest.mark.parametrize("encoding_name", list_encoding_names())
def test_fuzz_encode_and_count_match_tiktoken(encoding_name: str) -> None:
    ours = get_encoding(encoding_name)
    theirs = tiktoken.get_encoding(encoding_name)

    for text in _fuzz_cases():
        ours_tokens = ours.encode(text)
        theirs_tokens = theirs.encode(text)
        assert ours_tokens == theirs_tokens
        assert ours.count(text) == len(ours_tokens)
