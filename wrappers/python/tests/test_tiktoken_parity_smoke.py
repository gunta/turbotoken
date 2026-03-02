from __future__ import annotations

import pytest

from turbotoken import get_encoding, list_encoding_names

tiktoken = pytest.importorskip("tiktoken")

_CASES = [
    "",
    "hello world",
    "token counting for coding agents",
    "line one\nline two",
    "emoji: 🚀✅",
    "日本語のテキスト",
]


@pytest.mark.parametrize("encoding_name", list_encoding_names())
@pytest.mark.parametrize("text", _CASES)
def test_encode_matches_tiktoken_for_smoke_corpus(encoding_name: str, text: str) -> None:
    ours = get_encoding(encoding_name)
    theirs = tiktoken.get_encoding(encoding_name)
    assert ours.encode(text) == theirs.encode(text)


@pytest.mark.parametrize("encoding_name", list_encoding_names())
def test_special_token_policy_matches_tiktoken(encoding_name: str) -> None:
    ours = get_encoding(encoding_name)
    theirs = tiktoken.get_encoding(encoding_name)
    text = "x<|endoftext|>y"

    with pytest.raises(ValueError):
        ours.encode(text)
    with pytest.raises(ValueError):
        theirs.encode(text)

    assert ours.encode(text, allowed_special={"<|endoftext|>"}) == theirs.encode(
        text,
        allowed_special={"<|endoftext|>"},
    )
