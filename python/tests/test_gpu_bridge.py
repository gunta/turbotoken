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


def test_gpu_direct_settings_default_min_bytes() -> None:
    enabled, min_bytes, max_bytes, guard_enabled = _gpu._resolve_metal_bpe_direct_settings("", "", "", "")
    assert enabled is False
    assert min_bytes == 262_144
    assert max_bytes >= min_bytes
    assert guard_enabled is True


def test_gpu_overlap_adaptive_cold_start_prefers_serial_then_samples_overlap(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("TURBOTOKEN_GPU_OVERLAP_ADAPTIVE_ENABLE", "1")
    _gpu._overlap_perf_cache.clear()
    try:
        selected_overlap, key = _gpu._gpu_overlap_select_mode(
            total_batches=8,
            total_input_bytes=1_048_576,
            total_pieces=64,
        )
        assert selected_overlap is False
        assert key is not None

        _gpu._gpu_overlap_record_sample(key, used_overlap=False, elapsed_ms=10.0)
        selected_overlap_next, key_next = _gpu._gpu_overlap_select_mode(
            total_batches=8,
            total_input_bytes=1_048_576,
            total_pieces=64,
        )
        assert key_next == key
        assert selected_overlap_next is True
    finally:
        _gpu._overlap_perf_cache.clear()


def test_gpu_overlap_pipeline_min_avg_piece_bytes_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("TURBOTOKEN_GPU_OVERLAP_MIN_AVG_PIECE_BYTES", raising=False)
    assert _gpu._gpu_overlap_pipeline_min_avg_piece_bytes() == 2048


def test_gpu_profile_exposes_memory_fields_when_available() -> None:
    bridge = _gpu.get_metal_bridge()
    if not bridge.available:
        pytest.skip(f"Metal backend unavailable in this environment: {bridge.error}")

    payload = b"gpu-memory-check"
    encoded = bridge.encode_utf8_bytes(payload)
    assert encoded == [b for b in payload]

    profile = _gpu.profile_last()
    assert profile is not None
    for key in (
        "memory_active_bytes",
        "memory_working_set_bytes",
        "memory_device_allocated_bytes",
        "memory_device_recommended_working_set_bytes",
    ):
        assert key in profile
        assert isinstance(profile[key], int)
        assert profile[key] >= 0
