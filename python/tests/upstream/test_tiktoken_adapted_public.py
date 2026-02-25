from __future__ import annotations

"""Adapted from upstream tiktoken public tests.

Source files:
- upstream/tiktoken/tests/test_encoding.py
- upstream/tiktoken/tests/test_offsets.py
- upstream/tiktoken/tests/test_misc.py
"""

import pytest

import turbotoken

tiktoken = pytest.importorskip("tiktoken")

_ENCODINGS = ["r50k_base", "p50k_base", "cl100k_base", "o200k_base"]


def _common_prefix_len(a: str, b: str) -> int:
    idx = 0
    while idx < len(a) and idx < len(b) and a[idx] == b[idx]:
        idx += 1
    return idx


def _token_offsets_reference(enc: turbotoken.Encoding, tokens: list[int]) -> list[int]:
    text = enc.decode(tokens, errors="strict")
    out: list[int] = []
    for index in range(len(tokens)):
        prefix = enc.decode(tokens[:index], errors="ignore")
        out.append(_common_prefix_len(text, prefix))
    return out


@pytest.mark.parametrize("encoding_name", _ENCODINGS)
@pytest.mark.parametrize(
    "text",
    [
        "hello world",
        "token counting for coding agents",
        "line one\nline two",
        "ASCII punctuation !@#$%^&*()",
        "emoji: 🚀✅",
        "日本語のテキスト",
        "",
    ],
)
def test_encode_decode_matches_tiktoken_public_cases(encoding_name: str, text: str) -> None:
    ours = turbotoken.get_encoding(encoding_name)
    theirs = tiktoken.get_encoding(encoding_name)

    assert ours.encode(text) == theirs.encode(text)
    assert ours.decode(ours.encode(text)) == theirs.decode(theirs.encode(text))


def test_simple_regex_cases_match_cl100k_base() -> None:
    ours = turbotoken.get_encoding("cl100k_base")
    theirs = tiktoken.get_encoding("cl100k_base")

    for text in ["rer", "'rer", "today\n ", "today\n \n", "today\n  \n", " \x850"]:
        assert ours.encode(text) == theirs.encode(text)


@pytest.mark.parametrize("encoding_name", _ENCODINGS)
def test_large_repetition_roundtrip(encoding_name: str) -> None:
    ours = turbotoken.get_encoding(encoding_name)
    for char in ["^", "0", "a", "'s", " ", "\n"]:
        value = char * 10_000
        assert value == ours.decode(ours.encode(value))
        assert (" " + value + "\n") == ours.decode(ours.encode(" " + value + "\n"))


def test_surrogate_pair_behavior_matches_tiktoken() -> None:
    ours = turbotoken.get_encoding("cl100k_base")
    theirs = tiktoken.get_encoding("cl100k_base")

    assert ours.encode("👍") == theirs.encode("👍")
    assert ours.encode("\ud83d\udc4d") == theirs.encode("\ud83d\udc4d")
    assert ours.encode("\ud83d") == theirs.encode("\ud83d")


@pytest.mark.parametrize("encoding_name", _ENCODINGS)
def test_batch_encode_decode_matches_single(encoding_name: str) -> None:
    ours = turbotoken.get_encoding(encoding_name)
    batch = ["hello world", "goodbye world", "emoji 🚀✅", ""]

    encoded = ours.encode_batch(batch, allowed_special="all")
    assert encoded == [ours.encode(item, allowed_special="all") for item in batch]
    assert ours.decode_batch(encoded) == batch


def test_special_token_policies_match_cl100k_base() -> None:
    ours = turbotoken.get_encoding("cl100k_base")
    theirs = tiktoken.get_encoding("cl100k_base")
    text = "<|endoftext|> hello <|fim_prefix|> there <|fim_middle|>"

    with pytest.raises(ValueError):
        ours.encode(text)
    with pytest.raises(ValueError):
        theirs.encode(text)

    assert ours.encode(text, disallowed_special=()) == theirs.encode(text, disallowed_special=())
    assert ours.encode(text, allowed_special="all", disallowed_special=()) == theirs.encode(
        text,
        allowed_special="all",
        disallowed_special=(),
    )
    assert ours.encode(text, allowed_special={"<|fim_prefix|>"}, disallowed_special=()) == theirs.encode(
        text,
        allowed_special={"<|fim_prefix|>"},
        disallowed_special=(),
    )


@pytest.mark.parametrize("encoding_name", _ENCODINGS)
def test_single_token_roundtrip_subset(encoding_name: str) -> None:
    ours = turbotoken.get_encoding(encoding_name)
    limit = min(5_000, ours.n_vocab)

    for token in range(limit):
        try:
            token_bytes = ours.decode_single_token_bytes(token)
        except ValueError:
            continue
        assert ours.encode_single_token(token_bytes) == token


@pytest.mark.parametrize("encoding_name", ["cl100k_base", "o200k_base"])
def test_decode_with_offsets_matches_reference(encoding_name: str) -> None:
    ours = turbotoken.get_encoding(encoding_name)
    prompt = "hello world<|endoftext|> green cow"
    tokens = ours.encode(prompt, allowed_special="all")
    text, offsets = ours.decode_with_offsets(tokens)
    assert text == prompt
    assert offsets == _token_offsets_reference(ours, tokens)
