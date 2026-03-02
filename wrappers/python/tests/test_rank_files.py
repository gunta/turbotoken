from __future__ import annotations

from pathlib import Path

from turbotoken import get_encoding
from turbotoken._rank_files import (
    file_sha256,
    load_decoder_only,
    load_piece_bpe_cache,
    parse_rank_file_bytes,
    read_rank_file_native_payload,
    rank_file_path,
    save_piece_bpe_cache,
)


def test_rank_file_path_uses_encoding_name(tmp_path: Path) -> None:
    path = rank_file_path("o200k_base", dir_path=tmp_path)
    assert path == tmp_path / "o200k_base.tiktoken"


def test_parse_rank_file_bytes() -> None:
    payload = b"YQ== 1\nYg== 2\n"
    parsed = parse_rank_file_bytes(payload)
    assert parsed == {b"a": 1, b"b": 2}


def test_load_mergeable_ranks_downloads_to_cache(tmp_path: Path, monkeypatch) -> None:
    fixture = b"YQ== 1\nYg== 2\n"

    monkeypatch.setattr("turbotoken._rank_files._download_bytes", lambda *_args, **_kwargs: fixture)

    enc = get_encoding("o200k_base")
    ranks = enc.load_mergeable_ranks(cache_dir=tmp_path)
    assert ranks[b"a"] == 1

    cached = tmp_path / "o200k_base.tiktoken"
    assert cached.exists()
    assert file_sha256(cached)


def test_load_decoder_only_builds_cache(tmp_path: Path, monkeypatch) -> None:
    fixture = b"YQ== 1\nYg== 2\n"

    monkeypatch.setattr("turbotoken._rank_files._download_bytes", lambda *_args, **_kwargs: fixture)

    decoder = load_decoder_only("o200k_base", dir_path=tmp_path)
    assert decoder == {1: b"a", 2: b"b"}

    decoder_cache = tmp_path / "o200k_base.tiktoken.decoder.pickle"
    assert decoder_cache.exists()

    decoder_second = load_decoder_only("o200k_base", dir_path=tmp_path)
    assert decoder_second == decoder


def test_piece_bpe_cache_roundtrip(tmp_path: Path, monkeypatch) -> None:
    fixture = b"YQ== 1\nYg== 2\n"
    monkeypatch.setattr("turbotoken._rank_files._download_bytes", lambda *_args, **_kwargs: fixture)

    payload = {b"a": (1,), b"ab": (1, 2)}
    save_piece_bpe_cache("o200k_base", payload, dir_path=tmp_path)
    loaded = load_piece_bpe_cache("o200k_base", dir_path=tmp_path)
    assert loaded == payload


def test_read_rank_file_native_payload_builds_cache(tmp_path: Path, monkeypatch) -> None:
    fixture = b"YQ== 0\nYg== 2\n"
    monkeypatch.setattr("turbotoken._rank_files._download_bytes", lambda *_args, **_kwargs: fixture)

    payload = read_rank_file_native_payload("o200k_base", dir_path=tmp_path)
    assert payload.startswith(b"TTKRBIN1")

    native_cache = tmp_path / "o200k_base.tiktoken.native.bin"
    assert native_cache.exists()
    assert read_rank_file_native_payload("o200k_base", dir_path=tmp_path) == payload


def test_parse_rank_file_bytes_supports_native_payload(tmp_path: Path, monkeypatch) -> None:
    fixture = b"YQ== 0\nYg== 2\n"
    monkeypatch.setattr("turbotoken._rank_files._download_bytes", lambda *_args, **_kwargs: fixture)

    payload = read_rank_file_native_payload("o200k_base", dir_path=tmp_path)
    parsed = parse_rank_file_bytes(payload)
    assert parsed == {b"a": 0, b"b": 2}
