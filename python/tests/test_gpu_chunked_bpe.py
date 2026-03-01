from __future__ import annotations

import pytest

from turbotoken import get_encoding
from turbotoken import _gpu
from turbotoken._native import get_native_bridge


def test_encode_gpu_matches_encode_for_long_text() -> None:
    enc = get_encoding("o200k_base")
    text = ("hello world " * 2048) + "🚀" + (" abc123" * 1024)

    baseline = enc.encode(text)
    gpu_tokens = enc.encode_gpu(
        [text],
        chunk_bytes=4096,
        overlap_bytes=512,
        strict_verify=True,
    )[0]
    assert gpu_tokens == baseline


def test_count_gpu_matches_encode_lengths() -> None:
    enc = get_encoding("cl100k_base")
    texts = [
        "a" * 4096,
        "mixed utf8 🚀" * 1024,
        "line1\nline2\nline3\n" * 512,
    ]
    gpu_counts = enc.count_gpu(texts, chunk_bytes=2048, overlap_bytes=512, strict_verify=True)
    baseline_counts = [len(enc.encode(t)) for t in texts]
    assert gpu_counts == baseline_counts


def test_encode_gpu_respects_special_token_policies() -> None:
    enc = get_encoding("o200k_base")
    text = "x<|endoftext|>y"
    with pytest.raises(ValueError):
        enc.encode_gpu([text], chunk_bytes=1024, overlap_bytes=256)

    out = enc.encode_gpu(
        [text],
        chunk_bytes=1024,
        overlap_bytes=256,
        allowed_special={"<|endoftext|>"},
        disallowed_special="all",
    )[0]
    assert enc.eot_token in out


def test_chunked_stitch_matches_native_on_toy_ranks_when_native_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native bridge unavailable")

    ranks = b"YQ== 0\nYg== 1\nYw== 2\nYWI= 3\nYmM= 4\nYWJj 5\n"
    data = b"abcabcabcabc"
    exact = bridge.encode_bpe_from_ranks(ranks, data)
    if exact is None:
        pytest.skip("native bridge does not expose rank-based symbols")

    chunked = _gpu.encode_bpe_chunked_stitched(
        ranks,
        data,
        chunk_bytes=4,
        overlap_bytes=4,
        strict_verify=True,
    )
    assert chunked == exact


def test_chunked_stitch_metal_prefers_gpu_kernel_on_byte_level_ranks_when_available() -> None:
    native_bridge = get_native_bridge()
    metal_bridge = _gpu.get_metal_bridge()
    if not native_bridge.available or not metal_bridge.available:
        pytest.skip("native or metal bridge unavailable")

    # Byte-level-only toy ranks guarantee no cross-boundary merge differences.
    ranks = b"YQ== 0\nYg== 1\nYw== 2\n"
    data = (b"abc" * 4096) + b"cab"
    exact = native_bridge.encode_bpe_from_ranks(ranks, data)
    if exact is None:
        pytest.skip("native bridge does not expose rank-based symbols")

    chunked = _gpu.encode_bpe_chunked_stitched(
        ranks,
        data,
        chunk_bytes=1024,
        overlap_bytes=128,
        strict_verify=False,
        prefer_metal_stitch=True,
    )
    assert chunked == exact


def test_encode_gpu_auto_non_strict_matches_encode_for_long_piece() -> None:
    enc = get_encoding("o200k_base")
    text = "a" * 64_000
    baseline = enc.encode(text)
    auto_tokens = enc.encode_gpu(
        [text],
        device="auto",
        chunk_bytes=4096,
        overlap_bytes=512,
        strict_verify=False,
    )[0]
    assert auto_tokens == baseline


def test_encode_gpu_metal_non_strict_stays_byte_exact_for_long_piece() -> None:
    enc = get_encoding("o200k_base")
    text = "a" * 65_536
    metal_tokens = enc.encode_gpu(
        [text],
        device="metal",
        chunk_bytes=4096,
        overlap_bytes=512,
        strict_verify=False,
    )[0]
    assert enc.decode(metal_tokens) == text


def test_encode_gpu_overlap_toggle_matches_baseline(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    text = ("overlap pipeline validation " * 8192).strip()
    baseline = enc.encode(text)

    monkeypatch.setenv("TURBOTOKEN_GPU_OVERLAP_ENABLE", "0")
    no_overlap = enc.encode_gpu(
        [text],
        device="metal",
        chunk_bytes=4096,
        overlap_bytes=512,
        strict_verify=False,
    )[0]

    monkeypatch.setenv("TURBOTOKEN_GPU_OVERLAP_ENABLE", "1")
    with_overlap = enc.encode_gpu(
        [text],
        device="metal",
        chunk_bytes=4096,
        overlap_bytes=512,
        strict_verify=False,
    )[0]

    assert no_overlap == baseline
    assert with_overlap == baseline


def test_encode_gpu_range_batch_toggle_matches_baseline(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    text = ("range batch validation " * 16_384).strip()
    baseline = enc.encode(text)

    monkeypatch.setenv("TURBOTOKEN_METAL_FORCE_ALL_PIECES", "1")
    monkeypatch.setenv("TURBOTOKEN_GPU_OVERLAP_ENABLE", "0")
    monkeypatch.setenv("TURBOTOKEN_GPU_RANGE_BATCH_ENABLE", "1")
    monkeypatch.setenv("TURBOTOKEN_GPU_RANGE_BATCH_MIN_TEXT_BYTES", "1")
    monkeypatch.setenv("TURBOTOKEN_GPU_RANGE_BATCH_MIN_METAL_PIECES", "1")
    ranged = enc.encode_gpu(
        [text],
        device="metal",
        chunk_bytes=4096,
        overlap_bytes=512,
        strict_verify=False,
    )[0]
    assert ranged == baseline


def test_encode_gpu_force_all_pieces_ignores_min_metal_piece_default(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    text = ("normal text fixture slice " * 8192).strip()
    baseline = enc.encode(text)

    monkeypatch.setenv("TURBOTOKEN_METAL_FORCE_ALL_PIECES", "1")
    monkeypatch.setenv("TURBOTOKEN_GPU_OVERLAP_ENABLE", "0")
    monkeypatch.setenv("TURBOTOKEN_GPU_RANGE_BATCH_ENABLE", "1")
    monkeypatch.setenv("TURBOTOKEN_GPU_RANGE_BATCH_MIN_TEXT_BYTES", "1")
    monkeypatch.delenv("TURBOTOKEN_GPU_RANGE_BATCH_MIN_METAL_PIECES", raising=False)

    forced = enc.encode_gpu(
        [text],
        device="metal",
        chunk_bytes=4096,
        overlap_bytes=512,
        strict_verify=False,
    )[0]
    assert forced == baseline


def test_encode_gpu_force_all_pieces_emits_gpu_profile_for_short_normal_text(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    metal_bridge = _gpu.get_metal_bridge()
    if not metal_bridge.available:
        pytest.skip("metal bridge unavailable")

    enc = get_encoding("o200k_base")
    text = ("normal text fixture slice " * 2048).strip()
    baseline = enc.encode(text)

    monkeypatch.setenv("TURBOTOKEN_METAL_FORCE_ALL_PIECES", "1")
    monkeypatch.setenv("TURBOTOKEN_GPU_OVERLAP_ENABLE", "0")
    monkeypatch.setenv("TURBOTOKEN_GPU_RANGE_BATCH_ENABLE", "0")
    monkeypatch.setenv("TURBOTOKEN_METAL_BPE_DIRECT_ENABLE", "0")

    out = enc.encode_gpu(
        [text],
        device="metal",
        chunk_bytes=65536,
        overlap_bytes=256,
        strict_verify=False,
    )[0]
    assert out == baseline

    profile = _gpu.profile_last() or {}
    bpe_gpu_ns = int(profile.get("bpe_gpu_ns", 0))
    stitch_gpu_ns = int(profile.get("stitch_gpu_ns", 0))
    assert bpe_gpu_ns > 0 or stitch_gpu_ns > 0


def test_chunked_stitch_many_toy_ranges_match_exact_when_native_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native bridge unavailable")

    ranks = b"YQ== 0\nYg== 1\nYw== 2\nYWI= 3\nYmM= 4\nYWJj 5\n"
    data = b"abcabc|abcabc|abcabc"
    ranges = [(0, 6), (7, 13), (14, len(data))]
    exact_batch = bridge.encode_bpe_ranges_from_ranks(ranks, data, ranges)
    if exact_batch is None:
        pytest.skip("native bridge does not expose range symbols")
    exact_flat, exact_offsets = exact_batch

    many = _gpu.encode_bpe_chunked_stitched_many(
        ranks,
        data,
        ranges,
        chunk_bytes=4,
        overlap_bytes=4,
        strict_verify=True,
        prefer_metal_stitch=True,
    )
    assert many is not None
    many_flat, many_offsets = many
    assert many_offsets == exact_offsets
    assert many_flat == exact_flat
