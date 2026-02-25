from __future__ import annotations

import pytest

from turbotoken import _gpu


def test_gpu_backend_info_shape() -> None:
    info = _gpu.backend_info()
    assert isinstance(info["available"], bool)
    assert "error" in info
    assert "note" in info


def test_gpu_bridge_byte_path_roundtrip_when_available() -> None:
    bridge = _gpu.get_metal_bridge()
    if not bridge.available:
        pytest.skip(f"Metal backend unavailable in this environment: {bridge.error}")

    payload = b"Metal-fast-123"
    encoded = bridge.encode_utf8_bytes(payload)
    assert encoded == [b for b in payload]

    counted = bridge.count_nonzero_bytes(payload)
    assert counted == len(payload)

    batch = [b"abc", b"a\x00c", b""]
    batch_encoded = bridge.encode_utf8_bytes_batch(batch)
    assert batch_encoded == [[97, 98, 99], [97, 0, 99], []]

    batch_counts = bridge.count_nonzero_bytes_batch(batch)
    assert batch_counts == [3, 2, 0]

    flags = bridge.chunk_owner_flags(
        [0, 4, 8, 12],
        [0, 1, 1, 3],
        chunk_bytes=4,
        num_chunks=4,
    )
    assert flags == [1, 1, 0, 1]


def test_gpu_bpe_route_backend_shape() -> None:
    route = _gpu.bpe_route_backend(4096)
    assert route in {"none", "native", "metal"}
