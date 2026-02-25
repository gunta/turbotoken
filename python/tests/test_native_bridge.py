from __future__ import annotations

import pytest

from turbotoken._native import get_native_bridge


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
