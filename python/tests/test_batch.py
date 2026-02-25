from __future__ import annotations

from turbotoken import get_encoding


def test_encode_batch_matches_single_encode() -> None:
    enc = get_encoding("o200k_base")
    texts = ["hello", "world", "test"]
    assert enc.encode_batch(texts) == [enc.encode(t) for t in texts]


def test_encode_ordinary_batch_matches_single_encode_ordinary() -> None:
    enc = get_encoding("o200k_base")
    texts = ["a", "b", "c"]
    assert enc.encode_ordinary_batch(texts, num_threads=2) == [enc.encode_ordinary(t) for t in texts]


def test_decode_batch_matches_single_decode() -> None:
    enc = get_encoding("o200k_base")
    batch = [enc.encode("hello"), enc.encode("world")]
    assert enc.decode_batch(batch, num_threads=2) == [enc.decode(t) for t in batch]


def test_count_batch_matches_single_count() -> None:
    enc = get_encoding("o200k_base")
    texts = ["hello", "world"]
    assert enc.count_batch(texts) == [enc.count(t) for t in texts]
