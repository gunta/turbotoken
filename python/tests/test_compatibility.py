from __future__ import annotations

from turbotoken import encoding_for_model, get_encoding


def test_encoding_for_model_mapping() -> None:
    assert encoding_for_model("gpt-4").name == "cl100k_base"
    assert encoding_for_model("unknown-model").name == "o200k_base"


def test_encoding_has_core_tiktoken_like_properties() -> None:
    enc = get_encoding("o200k_base")
    assert isinstance(enc.name, str)
    assert isinstance(enc.n_vocab, int)
    assert isinstance(enc.eot_token, int)
    assert "<|endoftext|>" in enc.special_tokens_set


def test_token_byte_values_has_256_entries() -> None:
    enc = get_encoding("o200k_base")
    values = enc.token_byte_values()
    assert len(values) == 256
    assert values[0] == b"\x00"
