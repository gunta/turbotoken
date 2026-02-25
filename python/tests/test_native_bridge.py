from __future__ import annotations

import pytest

from turbotoken._native import get_native_bridge


def test_native_bridge_utf8_byte_wrappers_roundtrip_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    data = b"Hello, world!"
    tokens = bridge.encode_utf8_bytes(data)
    if tokens is None:
        pytest.skip("native library does not expose utf8 byte encode symbol")
    assert tokens == [72, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100, 33]
    assert bridge.decode_utf8_bytes(tokens) == data


def test_native_bridge_utf8_byte_wrappers_reject_invalid_tokens_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    if bridge.decode_utf8_bytes([65, 66, 67]) != b"ABC":
        pytest.skip("native library does not expose utf8 byte decode symbol")
    assert bridge.decode_utf8_bytes([65, 66, 300, 67]) is None


def test_native_bridge_utf8_scalar_wrappers_roundtrip_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    data = b"benchmark-check-1234"
    tokens = bridge.encode_utf8_bytes_scalar(data)
    if tokens is None:
        pytest.skip("native library does not expose utf8 scalar encode symbol")
    assert tokens == [b for b in data]
    assert bridge.decode_utf8_bytes_scalar(tokens) == data
    assert bridge.decode_utf8_bytes_scalar([65, 66, 300, 67]) is None


def test_native_bridge_bpe_wrappers_roundtrip_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    ranks = b"YQ== 0\nYg== 1\nYWI= 2\n"
    encoded = bridge.encode_bpe_from_ranks(ranks, b"abb")
    if encoded is None:
        pytest.skip("native library does not expose rank-based BPE symbols")
    counted = bridge.count_bpe_from_ranks(ranks, b"abb")
    if counted is None:
        pytest.skip("native library does not expose rank-based BPE count symbol")
    assert encoded == [2, 1]
    assert counted == 2
    assert bridge.decode_bpe_from_ranks(ranks, encoded) == b"abb"
