from __future__ import annotations

from pathlib import Path

from turbotoken import get_encoding
from turbotoken._rank_files import file_sha256, parse_rank_file_bytes, rank_file_path


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
