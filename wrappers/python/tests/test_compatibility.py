from __future__ import annotations

import pytest

from turbotoken import encoding_for_model, get_encoding


def test_encoding_for_model_mapping() -> None:
    assert encoding_for_model("gpt2").name == "gpt2"
    assert encoding_for_model("gpt-4").name == "cl100k_base"
    assert encoding_for_model("gpt-4o-2024-05-13").name == "o200k_base"
    assert encoding_for_model("text-davinci-003").name == "p50k_base"
    assert encoding_for_model("text-davinci-edit-001").name == "p50k_edit"
    assert encoding_for_model("gpt-oss-120b").name == "o200k_harmony"
    with pytest.raises(KeyError):
        encoding_for_model("unknown-model")


def test_encoding_has_core_tiktoken_like_properties() -> None:
    enc = get_encoding("o200k_base")
    assert isinstance(enc.name, str)
    assert isinstance(enc.n_vocab, int)
    assert isinstance(enc.eot_token, int)
    assert "<|endoftext|>" in enc.special_tokens_set


def test_token_byte_values_matches_mergeable_vocab() -> None:
    enc = get_encoding("o200k_base")
    values = enc.token_byte_values()
    assert len(values) == len(enc.load_mergeable_ranks())
    assert values[0] == b"\x00"


def test_internal_compatibility_accessors_exist() -> None:
    enc = get_encoding("cl100k_base")
    assert isinstance(enc.max_token_value, int)
    assert isinstance(enc._pat_str, str)
    assert "<|endoftext|>" in enc._special_tokens
    assert isinstance(enc._mergeable_ranks, dict)
    assert enc.decode_bytes(enc._encode_bytes(b" \xec\x8b\xa4\xed")) == b" \xec\x8b\xa4\xed"
