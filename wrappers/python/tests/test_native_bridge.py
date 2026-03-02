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


def test_native_bridge_non_ascii_count_wrappers_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    data = "ascii-🚀-κόσμε".encode("utf-8")
    expected = sum(1 for byte in data if byte & 0x80)

    auto = bridge.count_non_ascii_utf8(data)
    scalar = bridge.count_non_ascii_utf8_scalar(data)
    if auto is None or scalar is None:
        pytest.skip("native library does not expose non-ascii count symbols")

    assert auto == expected
    assert scalar == expected

    neon = bridge.count_non_ascii_utf8_neon(data)
    if neon is not None:
        assert neon == expected

    dotprod = bridge.count_non_ascii_utf8_dotprod(data)
    if dotprod is not None:
        assert dotprod == expected

    sme = bridge.count_non_ascii_utf8_sme(data)
    if sme is not None:
        assert sme == expected

    mask = bridge.arm64_feature_mask()
    kernel_id = bridge.count_non_ascii_kernel_id()
    if mask is not None and kernel_id is not None and mask != 0:
        assert kernel_id in (1, 2, 3)


def test_native_bridge_ascii_pretokenizer_ranges_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    data = b"hello  world"
    ranges = bridge.pretokenize_ascii_letter_space_ranges(data)
    if ranges is None:
        pytest.skip("native library does not expose ascii pretokenizer symbol")

    pieces = [data[start:end] for start, end in ranges]
    assert pieces == [b"hello", b" ", b" world"]
    assert bridge.pretokenize_ascii_letter_space_ranges(b"hello, world") is None


def _ascii_class(byte: int) -> int:
    if byte == 0x20:
        return 0
    if 65 <= byte <= 90 or 97 <= byte <= 122:
        return 1
    if 48 <= byte <= 57:
        return 2
    if 33 <= byte <= 126:
        return 3
    return 4


def test_native_bridge_ascii_boundary_count_wrappers_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    data = b"hello 123!! world\tz\xff"
    expected = 0
    if len(data) > 1:
        prev = _ascii_class(data[0])
        for byte in data[1:]:
            cls = _ascii_class(byte)
            if cls != prev:
                expected += 1
            prev = cls

    auto = bridge.count_ascii_class_boundaries_utf8(data)
    scalar = bridge.count_ascii_class_boundaries_utf8_scalar(data)
    if auto is None or scalar is None:
        pytest.skip("native library does not expose ascii boundary count symbols")

    assert auto == expected
    assert scalar == expected

    neon = bridge.count_ascii_class_boundaries_utf8_neon(data)
    if neon is not None:
        assert neon == expected


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


def test_native_bridge_bpe_token_limit_wrapper_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    ranks = b"YQ== 0\nYg== 1\nYWI= 2\n"
    within = bridge.is_within_token_limit_bpe_from_ranks(ranks, b"abb", 2)
    if within is None:
        pytest.skip("native library does not expose token-limit BPE symbol")
    assert within == 2
    assert bridge.is_within_token_limit_bpe_from_ranks(ranks, b"abb", 1) is False

    session = bridge.rank_session(ranks)
    if session is not None:
        assert session.is_within_token_limit_bpe(b"abb", 2) == 2
        assert session.is_within_token_limit_bpe(b"abb", 1) is False


def test_native_bridge_bpe_batch_wrapper_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    ranks = b"YQ== 0\nYg== 1\nYWI= 2\n"
    batch = bridge.encode_bpe_batch_from_ranks(ranks, b"abbabb", [0, 3, 6])
    if batch is None:
        pytest.skip("native library does not expose rank-based BPE batch symbol")

    tokens, token_offsets = batch
    assert tokens == [2, 1, 2, 1]
    assert token_offsets == [0, 2, 4]


def test_native_bridge_bpe_ranges_wrapper_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    ranks = b"YQ== 0\nYg== 1\nYWI= 2\n"
    batch = bridge.encode_bpe_ranges_from_ranks(ranks, b"abbabb", [(0, 3), (0, 3)])
    if batch is None:
        pytest.skip("native library does not expose rank-based BPE ranges symbol")

    tokens, token_offsets = batch
    assert tokens == [2, 1, 2, 1]
    assert token_offsets == [0, 2, 4]


def test_native_bridge_bpe_ranges_count_wrapper_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    ranks = b"YQ== 0\nYg== 1\nYWI= 2\n"
    counted = bridge.count_bpe_ranges_from_ranks(ranks, b"abbabb", [(0, 3), (0, 3)])
    if counted is None:
        pytest.skip("native library does not expose rank-based BPE ranges symbol")
    assert counted == 4


def test_native_bridge_bpe_ranges_layout_wrapper_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    ranks = b"YQ== 0\nYg== 1\nYWI= 2\n"
    batch = bridge.encode_bpe_ranges_from_ranks(ranks, b"ababab", [(0, 4), (2, 6)])
    if batch is None:
        pytest.skip("native library does not expose rank-based BPE ranges symbol")

    tokens, token_offsets = batch
    layout = bridge.bpe_ranges_token_layout_from_ranks(
        ranks,
        input_len=6,
        starts=[0, 2],
        ends=[4, 6],
        tokens=tokens,
        token_offsets=token_offsets,
        source_chunk_base=5,
        chunk_bytes=4,
        num_chunks=16,
    )
    if layout is None:
        pytest.skip("native library does not expose bpe ranges token layout symbol")

    token_starts, source_chunks = layout
    assert token_starts == [0, 2, 2, 4]
    assert source_chunks == [5, 5, 6, 6]


def test_native_bridge_filter_tokens_wrapper_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    filtered = bridge.filter_tokens_by_keep_flags(
        [11, 22, 33, 44, 55],
        [1, 0, 1, 0, 1],
    )
    if filtered is None:
        pytest.skip("native library does not expose token-filter symbol")

    assert filtered == [11, 33, 55]


def test_native_bridge_chunked_stitch_wrapper_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    ranks = b"YQ== 0\nYg== 1\nYw== 2\n"
    data = b"abcabcabcabc"
    exact = bridge.encode_bpe_from_ranks(ranks, data)
    if exact is None:
        pytest.skip("native library does not expose rank-based BPE symbols")

    chunked = bridge.encode_bpe_chunked_stitched_from_ranks(
        ranks,
        data,
        chunk_bytes=4,
        overlap_bytes=4,
    )
    if chunked is None:
        pytest.skip("native library does not expose chunked stitch symbol")
    assert chunked == exact


def test_native_bridge_bpe_file_wrappers_when_available(tmp_path) -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    ranks = b"YQ== 0\nYg== 1\nYWI= 2\n"
    file_path = tmp_path / "sample.txt"
    file_path.write_bytes(b"abb")

    encoded = bridge.encode_bpe_file_from_ranks(ranks, file_path)
    if encoded is None:
        pytest.skip("native library does not expose file-path BPE symbols")
    assert encoded == [2, 1]

    counted = bridge.count_bpe_file_from_ranks(ranks, file_path)
    if counted is None:
        pytest.skip("native library does not expose file-path BPE count symbol")
    assert counted == 2

    within = bridge.is_within_token_limit_bpe_file_from_ranks(ranks, file_path, 2)
    if within is None:
        pytest.skip("native library does not expose file-path token-limit BPE symbol")
    assert within == 2
    assert bridge.is_within_token_limit_bpe_file_from_ranks(ranks, file_path, 1) is False

    session = bridge.rank_session(ranks)
    if session is not None:
        assert session.encode_bpe_file(file_path) == [2, 1]
        assert session.count_bpe_file(file_path) == 2
        assert session.is_within_token_limit_bpe_file(file_path, 2) == 2
        assert session.is_within_token_limit_bpe_file(file_path, 1) is False


def test_native_bridge_ascii_letter_space_bpe_wrappers_when_available() -> None:
    bridge = get_native_bridge()
    if not bridge.available:
        pytest.skip("native library not available in this environment")

    ranks = b"YQ== 0\nYg== 1\nYWI= 2\nIA== 3\n"
    data = b"ab ab"

    counted = bridge.count_bpe_ascii_letter_space_from_ranks(ranks, data)
    if counted is None:
        pytest.skip("native library does not expose ascii-letter-space BPE count symbol")
    assert counted == 3

    encoded = bridge.encode_bpe_ascii_letter_space_from_ranks(ranks, data)
    if encoded is None:
        pytest.skip("native library does not expose ascii-letter-space BPE encode symbol")
    assert encoded == [2, 3, 2]

    session = bridge.rank_session(ranks)
    if session is not None:
        assert session.count_bpe_ascii_letter_space(data) == 3
        assert session.encode_bpe_ascii_letter_space(data) == [2, 3, 2]
