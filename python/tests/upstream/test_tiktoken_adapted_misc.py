from __future__ import annotations

"""Additional adapters from upstream tiktoken misc/encoding tests."""

import pytest

import turbotoken

tiktoken = pytest.importorskip("tiktoken")


@pytest.mark.parametrize(
    "model_name",
    [
        "gpt2",
        "text-davinci-003",
        "text-davinci-edit-001",
        "gpt-3.5-turbo-0301",
        "gpt-4",
        "gpt-4o",
        "gpt-oss-120b",
    ],
)
def test_encoding_for_model_matches_tiktoken(model_name: str) -> None:
    ours = turbotoken.encoding_for_model(model_name)
    theirs = tiktoken.encoding_for_model(model_name)
    assert ours.name == theirs.name


def test_encode_bytes_roundtrip_matches_tiktoken() -> None:
    ours = turbotoken.get_encoding("cl100k_base")
    theirs = tiktoken.get_encoding("cl100k_base")

    sample = b" \xec\x8b\xa4\xed"
    assert ours._encode_bytes(sample) == theirs._encode_bytes(sample)
    assert ours.decode_bytes(ours._encode_bytes(sample)) == sample

    for i in range(10):
        payload = b"\x80" * i
        assert ours.decode_bytes(ours._encode_bytes(payload)) == payload


def test_core_internal_attribute_shapes_match_tiktoken() -> None:
    ours = turbotoken.get_encoding("cl100k_base")
    theirs = tiktoken.get_encoding("cl100k_base")

    assert isinstance(ours.max_token_value, int)
    assert ours.max_token_value == theirs.max_token_value
    assert ours._pat_str == theirs._pat_str
    assert ours._special_tokens == theirs._special_tokens
