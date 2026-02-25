from __future__ import annotations

import pytest

from turbotoken import get_encoding


def test_empty_string() -> None:
    enc = get_encoding("o200k_base")
    assert enc.encode("") == []
    assert enc.decode([]) == ""
    assert enc.count("") == 0


def test_decode_rejects_out_of_range_token() -> None:
    enc = get_encoding("o200k_base")
    with pytest.raises(ValueError):
        enc.decode([enc.n_vocab + 1])


def test_decode_single_token_bytes_for_special_token() -> None:
    enc = get_encoding("o200k_base")
    assert enc.decode_single_token_bytes(enc.eot_token) == b"<|endoftext|>"
