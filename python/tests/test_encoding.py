from __future__ import annotations

import pytest

from turbotoken import get_encoding, list_encoding_names


def test_roundtrip_utf8_bytes_placeholder() -> None:
    enc = get_encoding("o200k_base")
    text = "hello"
    assert enc.decode(enc.encode(text)) == text


def test_list_encoding_names_contains_core_encodings() -> None:
    names = list_encoding_names()
    assert names == ["cl100k_base", "o200k_base", "p50k_base", "r50k_base"]


def test_unknown_encoding_raises_value_error() -> None:
    with pytest.raises(ValueError):
        get_encoding("not_real")


def test_special_token_disallowed_by_default() -> None:
    enc = get_encoding("o200k_base")
    with pytest.raises(ValueError):
        enc.encode("x<|endoftext|>y")


def test_special_token_allowed_maps_to_placeholder_id() -> None:
    enc = get_encoding("o200k_base")
    out = enc.encode("x<|endoftext|>y", allowed_special={"<|endoftext|>"})
    assert enc.eot_token in out


def test_count_with_allowed_special_counts_one_token_for_placeholder_special() -> None:
    enc = get_encoding("o200k_base")
    assert enc.count("x<|endoftext|>y", allowed_special={"<|endoftext|>"}) == 3


def test_encode_single_token_accepts_single_byte_and_special() -> None:
    enc = get_encoding("o200k_base")
    assert enc.encode_single_token("a") == ord("a")
    assert enc.encode_single_token(b"a") == ord("a")
    assert enc.encode_single_token("<|endoftext|>") == enc.eot_token


def test_encode_single_token_rejects_multibyte_input() -> None:
    enc = get_encoding("o200k_base")
    with pytest.raises(KeyError):
        enc.encode_single_token("ab")
