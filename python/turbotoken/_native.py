"""Native bridge utilities for loading Zig C ABI exports via cffi."""

from __future__ import annotations

import os
import platform
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

try:
    from cffi import FFI
except ModuleNotFoundError:  # pragma: no cover - handled at runtime in bridge state
    FFI = None  # type: ignore[assignment]


def _shared_library_names() -> list[str]:
    if os.name == "nt":
        return ["turbotoken.dll"]
    if platform.system() == "Darwin":
        return ["libturbotoken.dylib", "turbotoken.dylib"]
    return ["libturbotoken.so"]


def _candidate_library_paths() -> list[Path]:
    package_dir = Path(__file__).resolve().parent
    repo_root = package_dir.parents[2]

    candidates: list[Path] = []

    env_path = os.environ.get("TURBOTOKEN_NATIVE_LIB")
    if env_path:
        candidates.append(Path(env_path).expanduser())

    search_dirs = [
        package_dir,
        package_dir / ".libs",
        repo_root / "zig-out" / "lib",
        Path.cwd() / "zig-out" / "lib",
    ]
    for directory in search_dirs:
        for lib_name in _shared_library_names():
            candidates.append(directory / lib_name)

    deduped: list[Path] = []
    seen: set[str] = set()
    for candidate in candidates:
        key = str(candidate)
        if key in seen:
            continue
        seen.add(key)
        deduped.append(candidate)
    return deduped


def _unpack_u32(ffi: Any, out: Any, written: int) -> list[int]:
    if written <= 0:
        return []
    try:
        return list(ffi.unpack(out, written))
    except AttributeError:
        return [int(out[idx]) for idx in range(written)]


@dataclass(slots=True)
class NativeBridge:
    _lib: Any | None = None
    _ffi: Any | None = None
    _error: str | None = None
    _rank_payload_ref: bytes | None = None
    _rank_payload_buf: Any | None = None

    def load(self) -> None:
        if self._lib is not None or self._error is not None:
            return

        if FFI is None:
            self._error = "cffi is not installed"
            return

        ffi = FFI()
        ffi.cdef(
            """
            const char *turbotoken_version(void);
            long turbotoken_count(const char *text, size_t text_len);
            long turbotoken_pretokenize_ascii_letter_space_ranges(
                const char *text,
                size_t text_len,
                uint32_t *out_starts,
                uint32_t *out_ends,
                size_t out_cap
            );
            long turbotoken_pretokenize_ascii_o200k_ranges(
                const char *text,
                size_t text_len,
                uint32_t *out_starts,
                uint32_t *out_ends,
                size_t out_cap
            );
            unsigned long long turbotoken_arm64_feature_mask(void);
            unsigned int turbotoken_count_non_ascii_kernel_id(void);
            long turbotoken_count_non_ascii_utf8(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_non_ascii_utf8_scalar(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_non_ascii_utf8_neon(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_non_ascii_utf8_dotprod(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_non_ascii_utf8_sme(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_ascii_class_boundaries_utf8(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_ascii_class_boundaries_utf8_scalar(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_ascii_class_boundaries_utf8_neon(
                const char *text,
                size_t text_len
            );
            long turbotoken_encode_utf8_bytes(
                const char *text,
                size_t text_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_encode_utf8_bytes_scalar(
                const char *text,
                size_t text_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_decode_utf8_bytes(
                const uint32_t *tokens,
                size_t token_len,
                unsigned char *out_bytes,
                size_t out_cap
            );
            long turbotoken_decode_utf8_bytes_scalar(
                const uint32_t *tokens,
                size_t token_len,
                unsigned char *out_bytes,
                size_t out_cap
            );
            long turbotoken_encode_bpe_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_train_bpe_from_chunk_counts(
                const char *chunks,
                size_t chunks_len,
                const uint32_t *chunk_offsets,
                size_t chunk_offsets_len,
                const uint32_t *chunk_counts,
                size_t chunk_counts_len,
                uint32_t vocab_size,
                uint32_t min_frequency,
                uint32_t *out_merges,
                size_t out_cap
            );
            long turbotoken_train_bpe_ascii_o200k(
                const char *text,
                size_t text_len,
                uint32_t vocab_size,
                uint32_t min_frequency,
                uint32_t *out_merges,
                size_t out_cap
            );
            long turbotoken_train_bpe_ascii_o200k_multi(
                const char *texts,
                size_t texts_len,
                const uint32_t *text_offsets,
                size_t text_offsets_len,
                uint32_t vocab_size,
                uint32_t min_frequency,
                uint32_t *out_merges,
                size_t out_cap
            );
            long turbotoken_encode_bpe_batch_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                const uint32_t *offsets,
                size_t offsets_len,
                uint32_t *out_tokens,
                size_t out_cap,
                uint32_t *out_token_offsets,
                size_t out_token_offsets_len
            );
            long turbotoken_encode_bpe_ranges_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                const uint32_t *range_starts,
                const uint32_t *range_ends,
                size_t ranges_len,
                uint32_t *out_tokens,
                size_t out_cap,
                uint32_t *out_token_offsets,
                size_t out_token_offsets_len
            );
            long turbotoken_bpe_ranges_token_layout_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                size_t input_len,
                const uint32_t *range_starts,
                const uint32_t *range_ends,
                size_t ranges_len,
                const uint32_t *tokens,
                size_t token_len,
                const uint32_t *token_offsets,
                size_t token_offsets_len,
                uint32_t source_chunk_base,
                uint32_t chunk_bytes,
                uint32_t num_chunks,
                uint32_t *out_token_starts,
                uint32_t *out_source_chunks,
                size_t out_cap
            );
            long turbotoken_filter_tokens_by_keep_flags(
                const uint32_t *tokens,
                const uint32_t *keep_flags,
                size_t token_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_encode_bpe_chunked_stitched_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                size_t chunk_bytes,
                size_t overlap_bytes,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_count_bpe_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len
            );
            long turbotoken_count_bpe_ascii_o200k_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len
            );
            long turbotoken_encode_bpe_ascii_o200k_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_decode_bpe_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const uint32_t *tokens,
                size_t token_len,
                unsigned char *out_bytes,
                size_t out_cap
            );
            """
        )

        for path in _candidate_library_paths():
            if not path.exists():
                continue
            try:
                self._lib = ffi.dlopen(str(path))
                self._ffi = ffi
                return
            except OSError as exc:
                self._error = f"failed to load {path}: {exc}"
                return

        self._error = "native library not found"

    @property
    def available(self) -> bool:
        self.load()
        return self._lib is not None

    @property
    def error(self) -> str | None:
        self.load()
        return self._error

    def version(self) -> str | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        raw = self._lib.turbotoken_version()
        if raw == self._ffi.NULL:
            return None
        return self._ffi.string(raw).decode("utf-8")

    def _rank_payload_ptr(self, rank_payload: bytes) -> Any | None:
        self.load()
        if self._ffi is None:
            return None
        if self._rank_payload_ref is not rank_payload or self._rank_payload_buf is None:
            self._rank_payload_ref = rank_payload
            self._rank_payload_buf = self._ffi.from_buffer("const char[]", rank_payload)
        return self._rank_payload_buf

    def count_bytes(self, data: bytes) -> int | None:
        self.load()
        if self._lib is None:
            return None

        result = int(self._lib.turbotoken_count(data, len(data)))
        if result < 0:
            return None
        return result

    def pretokenize_ascii_letter_space_ranges(
        self,
        data: bytes,
    ) -> list[tuple[int, int]] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        try:
            needed = int(
                self._lib.turbotoken_pretokenize_ascii_letter_space_ranges(
                    data,
                    len(data),
                    self._ffi.NULL,
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        starts = self._ffi.new("uint32_t[]", needed)
        ends = self._ffi.new("uint32_t[]", needed)
        try:
            written = int(
                self._lib.turbotoken_pretokenize_ascii_letter_space_ranges(
                    data,
                    len(data),
                    starts,
                    ends,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return [(int(starts[idx]), int(ends[idx])) for idx in range(written)]

    def pretokenize_ascii_o200k_ranges(
        self,
        data: bytes,
    ) -> list[tuple[int, int]] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        try:
            needed = int(
                self._lib.turbotoken_pretokenize_ascii_o200k_ranges(
                    data,
                    len(data),
                    self._ffi.NULL,
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        starts = self._ffi.new("uint32_t[]", needed)
        ends = self._ffi.new("uint32_t[]", needed)
        try:
            written = int(
                self._lib.turbotoken_pretokenize_ascii_o200k_ranges(
                    data,
                    len(data),
                    starts,
                    ends,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return [(int(starts[idx]), int(ends[idx])) for idx in range(written)]

    def arm64_feature_mask(self) -> int | None:
        self.load()
        if self._lib is None:
            return None

        try:
            return int(self._lib.turbotoken_arm64_feature_mask())
        except (AttributeError, TypeError):
            return None

    def count_non_ascii_kernel_id(self) -> int | None:
        self.load()
        if self._lib is None:
            return None

        try:
            return int(self._lib.turbotoken_count_non_ascii_kernel_id())
        except (AttributeError, TypeError):
            return None

    def _count_non_ascii(self, symbol: str, data: bytes) -> int | None:
        self.load()
        if self._lib is None:
            return None

        try:
            fn = getattr(self._lib, symbol)
            result = int(fn(data, len(data)))
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def count_non_ascii_utf8(self, data: bytes) -> int | None:
        return self._count_non_ascii("turbotoken_count_non_ascii_utf8", data)

    def count_non_ascii_utf8_scalar(self, data: bytes) -> int | None:
        return self._count_non_ascii("turbotoken_count_non_ascii_utf8_scalar", data)

    def count_non_ascii_utf8_neon(self, data: bytes) -> int | None:
        return self._count_non_ascii("turbotoken_count_non_ascii_utf8_neon", data)

    def count_non_ascii_utf8_dotprod(self, data: bytes) -> int | None:
        return self._count_non_ascii("turbotoken_count_non_ascii_utf8_dotprod", data)

    def count_non_ascii_utf8_sme(self, data: bytes) -> int | None:
        return self._count_non_ascii("turbotoken_count_non_ascii_utf8_sme", data)

    def _count_ascii_boundaries(self, symbol: str, data: bytes) -> int | None:
        self.load()
        if self._lib is None:
            return None

        try:
            fn = getattr(self._lib, symbol)
            result = int(fn(data, len(data)))
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def count_ascii_class_boundaries_utf8(self, data: bytes) -> int | None:
        return self._count_ascii_boundaries("turbotoken_count_ascii_class_boundaries_utf8", data)

    def count_ascii_class_boundaries_utf8_scalar(self, data: bytes) -> int | None:
        return self._count_ascii_boundaries("turbotoken_count_ascii_class_boundaries_utf8_scalar", data)

    def count_ascii_class_boundaries_utf8_neon(self, data: bytes) -> int | None:
        return self._count_ascii_boundaries("turbotoken_count_ascii_class_boundaries_utf8_neon", data)

    def encode_utf8_bytes(self, data: bytes) -> list[int] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        try:
            needed = int(self._lib.turbotoken_encode_utf8_bytes(data, len(data), self._ffi.NULL, 0))
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        out = self._ffi.new("uint32_t[]", needed)
        try:
            written = int(self._lib.turbotoken_encode_utf8_bytes(data, len(data), out, needed))
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def decode_utf8_bytes(self, tokens: list[int]) -> bytes | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        token_buf = self._ffi.new("uint32_t[]", tokens)
        try:
            needed = int(self._lib.turbotoken_decode_utf8_bytes(token_buf, len(tokens), self._ffi.NULL, 0))
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return b""

        out = self._ffi.new("unsigned char[]", needed)
        try:
            written = int(
                self._lib.turbotoken_decode_utf8_bytes(
                    token_buf,
                    len(tokens),
                    out,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return bytes(self._ffi.buffer(out, written))

    def encode_utf8_bytes_scalar(self, data: bytes) -> list[int] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        try:
            needed = int(
                self._lib.turbotoken_encode_utf8_bytes_scalar(data, len(data), self._ffi.NULL, 0)
            )
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        out = self._ffi.new("uint32_t[]", needed)
        try:
            written = int(
                self._lib.turbotoken_encode_utf8_bytes_scalar(data, len(data), out, needed)
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def decode_utf8_bytes_scalar(self, tokens: list[int]) -> bytes | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        token_buf = self._ffi.new("uint32_t[]", tokens)
        try:
            needed = int(
                self._lib.turbotoken_decode_utf8_bytes_scalar(
                    token_buf,
                    len(tokens),
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return b""

        out = self._ffi.new("unsigned char[]", needed)
        try:
            written = int(
                self._lib.turbotoken_decode_utf8_bytes_scalar(
                    token_buf,
                    len(tokens),
                    out,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return bytes(self._ffi.buffer(out, written))

    def encode_bpe_from_ranks(self, rank_payload: bytes, data: bytes) -> list[int] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        try:
            needed = int(
                self._lib.turbotoken_encode_bpe_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    data,
                    len(data),
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        out = self._ffi.new("uint32_t[]", needed)
        try:
            written = int(
                self._lib.turbotoken_encode_bpe_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    data,
                    len(data),
                    out,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def train_bpe_from_chunk_counts(
        self,
        chunks: bytes,
        offsets: list[int],
        counts: list[int],
        *,
        vocab_size: int,
        min_frequency: int,
    ) -> list[tuple[int, int, int]] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        if vocab_size < 256 or min_frequency < 1:
            return None
        if len(offsets) == 0 or len(counts) + 1 != len(offsets):
            return None
        if offsets[0] != 0 or offsets[-1] != len(chunks):
            return None

        prev = 0
        for value in offsets:
            if value < prev or value < 0 or value > len(chunks) or value > 0xFFFFFFFF:
                return None
            prev = value
        for count in counts:
            if count < 0 or count > 0xFFFFFFFF:
                return None

        chunk_buf = self._ffi.from_buffer("const char[]", chunks)
        offsets_buf = self._ffi.new("uint32_t[]", offsets)
        counts_buf = self._ffi.new("uint32_t[]", counts)

        try:
            needed = int(
                self._lib.turbotoken_train_bpe_from_chunk_counts(
                    chunk_buf,
                    len(chunks),
                    offsets_buf,
                    len(offsets),
                    counts_buf,
                    len(counts),
                    vocab_size,
                    min_frequency,
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        flat_len = needed * 3
        out = self._ffi.new("uint32_t[]", flat_len)
        try:
            written = int(
                self._lib.turbotoken_train_bpe_from_chunk_counts(
                    chunk_buf,
                    len(chunks),
                    offsets_buf,
                    len(offsets),
                    counts_buf,
                    len(counts),
                    vocab_size,
                    min_frequency,
                    out,
                    flat_len,
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if written < 0:
            return None

        merges: list[tuple[int, int, int]] = []
        for idx in range(written):
            base = idx * 3
            merges.append((int(out[base]), int(out[base + 1]), int(out[base + 2])))
        return merges

    def train_bpe_ascii_o200k(
        self,
        text: bytes,
        *,
        vocab_size: int,
        min_frequency: int,
    ) -> list[tuple[int, int, int]] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        if vocab_size < 256 or min_frequency < 1:
            return None

        in_buf = self._ffi.from_buffer("const char[]", text)
        try:
            needed = int(
                self._lib.turbotoken_train_bpe_ascii_o200k(
                    in_buf,
                    len(text),
                    vocab_size,
                    min_frequency,
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        flat_len = needed * 3
        out = self._ffi.new("uint32_t[]", flat_len)
        try:
            written = int(
                self._lib.turbotoken_train_bpe_ascii_o200k(
                    in_buf,
                    len(text),
                    vocab_size,
                    min_frequency,
                    out,
                    flat_len,
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if written < 0:
            return None

        merges: list[tuple[int, int, int]] = []
        for idx in range(written):
            base = idx * 3
            merges.append((int(out[base]), int(out[base + 1]), int(out[base + 2])))
        return merges

    def train_bpe_ascii_o200k_multi(
        self,
        texts: bytes,
        offsets: list[int],
        *,
        vocab_size: int,
        min_frequency: int,
    ) -> list[tuple[int, int, int]] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        if vocab_size < 256 or min_frequency < 1:
            return None
        if len(offsets) == 0 or offsets[0] != 0 or offsets[-1] != len(texts):
            return None

        prev = 0
        for value in offsets:
            if value < prev or value < 0 or value > len(texts) or value > 0xFFFFFFFF:
                return None
            prev = value

        in_buf = self._ffi.from_buffer("const char[]", texts)
        try:
            offsets_buf = self._ffi.new("uint32_t[]", offsets)
            needed = int(
                self._lib.turbotoken_train_bpe_ascii_o200k_multi(
                    in_buf,
                    len(texts),
                    offsets_buf,
                    len(offsets),
                    vocab_size,
                    min_frequency,
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        flat_len = needed * 3
        out = self._ffi.new("uint32_t[]", flat_len)
        try:
            written = int(
                self._lib.turbotoken_train_bpe_ascii_o200k_multi(
                    in_buf,
                    len(texts),
                    offsets_buf,
                    len(offsets),
                    vocab_size,
                    min_frequency,
                    out,
                    flat_len,
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if written < 0:
            return None

        merges: list[tuple[int, int, int]] = []
        for idx in range(written):
            base = idx * 3
            merges.append((int(out[base]), int(out[base + 1]), int(out[base + 2])))
        return merges

    def encode_bpe_batch_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        offsets: list[int],
    ) -> tuple[list[int], list[int]] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        if len(offsets) == 0:
            return None
        if len(data) > 0xFFFFFFFF:
            return None
        if offsets[0] != 0 or offsets[-1] != len(data):
            return None
        prev = 0
        for value in offsets:
            if value < prev or value < 0 or value > len(data) or value > 0xFFFFFFFF:
                return None
            prev = value

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            offsets_buf = self._ffi.new("uint32_t[]", offsets)
            token_offsets = self._ffi.new("uint32_t[]", len(offsets))
            # BPE output token count is bounded by input bytes, so one pass is enough.
            out = self._ffi.new("uint32_t[]", max(1, len(data)))
        except (OverflowError, TypeError):
            return None
        try:
            written = int(
                self._lib.turbotoken_encode_bpe_batch_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    offsets_buf,
                    len(offsets),
                    out,
                    len(data),
                    token_offsets,
                    len(offsets),
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None

        return (
            _unpack_u32(self._ffi, out, written),
            _unpack_u32(self._ffi, token_offsets, len(offsets)),
        )

    def encode_bpe_ranges_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        ranges: list[tuple[int, int]],
    ) -> tuple[list[int], list[int]] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        if len(data) > 0xFFFFFFFF:
            return None
        starts: list[int] = []
        ends: list[int] = []
        upper_bound = 0
        for start, end in ranges:
            if start < 0 or end < start or end > len(data) or end > 0xFFFFFFFF:
                return None
            starts.append(start)
            ends.append(end)
            upper_bound += end - start
            if upper_bound > 0x7FFFFFFF_FFFFFFFF:
                return None

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            starts_buf = self._ffi.new("uint32_t[]", starts)
            ends_buf = self._ffi.new("uint32_t[]", ends)
            token_offsets = self._ffi.new("uint32_t[]", len(ranges) + 1)
            out = self._ffi.new("uint32_t[]", max(1, upper_bound))
        except (OverflowError, TypeError):
            return None

        try:
            written = int(
                self._lib.turbotoken_encode_bpe_ranges_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    starts_buf,
                    ends_buf,
                    len(ranges),
                    out,
                    upper_bound,
                    token_offsets,
                    len(ranges) + 1,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return (
            _unpack_u32(self._ffi, out, written),
            _unpack_u32(self._ffi, token_offsets, len(ranges) + 1),
        )

    def count_bpe_ranges_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        ranges: list[tuple[int, int]],
    ) -> int | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        if len(data) > 0xFFFFFFFF:
            return None
        starts: list[int] = []
        ends: list[int] = []
        for start, end in ranges:
            if start < 0 or end < start or end > len(data) or end > 0xFFFFFFFF:
                return None
            starts.append(start)
            ends.append(end)

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            starts_buf = self._ffi.new("uint32_t[]", starts)
            ends_buf = self._ffi.new("uint32_t[]", ends)
            result = int(
                self._lib.turbotoken_encode_bpe_ranges_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    starts_buf,
                    ends_buf,
                    len(ranges),
                    self._ffi.NULL,
                    0,
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def encode_bpe_chunked_stitched_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        *,
        chunk_bytes: int,
        overlap_bytes: int,
    ) -> list[int] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None
        if chunk_bytes <= 0 or overlap_bytes <= 0:
            return None

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            out = self._ffi.new("uint32_t[]", max(1, len(data)))
            written = int(
                self._lib.turbotoken_encode_bpe_chunked_stitched_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    chunk_bytes,
                    overlap_bytes,
                    out,
                    len(data),
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def bpe_ranges_token_layout_from_ranks(
        self,
        rank_payload: bytes,
        *,
        input_len: int,
        starts: list[int],
        ends: list[int],
        tokens: list[int],
        token_offsets: list[int],
        source_chunk_base: int,
        chunk_bytes: int,
        num_chunks: int,
    ) -> tuple[list[int], list[int]] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        if input_len < 0 or input_len > 0xFFFFFFFF:
            return None
        if chunk_bytes <= 0 or chunk_bytes > 0xFFFFFFFF:
            return None
        if num_chunks <= 0 or num_chunks > 0xFFFFFFFF:
            return None
        if source_chunk_base < 0 or source_chunk_base > 0xFFFFFFFF:
            return None
        if len(starts) != len(ends):
            return None
        if len(token_offsets) != len(starts) + 1:
            return None
        if len(tokens) > 0xFFFFFFFF:
            return None

        for start, end in zip(starts, ends):
            if start < 0 or end < start or end > input_len or end > 0xFFFFFFFF:
                return None

        prev = 0
        for value in token_offsets:
            if value < prev or value < 0 or value > len(tokens) or value > 0xFFFFFFFF:
                return None
            prev = value

        try:
            starts_buf = self._ffi.new("uint32_t[]", starts)
            ends_buf = self._ffi.new("uint32_t[]", ends)
            tokens_buf = self._ffi.new("uint32_t[]", tokens)
            offsets_buf = self._ffi.new("uint32_t[]", token_offsets)
            out_starts = self._ffi.new("uint32_t[]", max(1, len(tokens)))
            out_chunks = self._ffi.new("uint32_t[]", max(1, len(tokens)))
        except (OverflowError, TypeError):
            return None

        try:
            written = int(
                self._lib.turbotoken_bpe_ranges_token_layout_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    input_len,
                    starts_buf,
                    ends_buf,
                    len(starts),
                    tokens_buf,
                    len(tokens),
                    offsets_buf,
                    len(token_offsets),
                    source_chunk_base,
                    chunk_bytes,
                    num_chunks,
                    out_starts,
                    out_chunks,
                    len(tokens),
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return (
            _unpack_u32(self._ffi, out_starts, written),
            _unpack_u32(self._ffi, out_chunks, written),
        )

    def filter_tokens_by_keep_flags(
        self,
        tokens: list[int],
        keep_flags: list[int],
    ) -> list[int] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        if len(tokens) != len(keep_flags):
            return None
        if len(tokens) > 0xFFFFFFFF:
            return None
        if len(tokens) == 0:
            return []

        try:
            token_buf = self._ffi.new("uint32_t[]", tokens)
            flag_buf = self._ffi.new("uint32_t[]", keep_flags)
        except (OverflowError, TypeError):
            return None

        try:
            needed = int(
                self._lib.turbotoken_filter_tokens_by_keep_flags(
                    token_buf,
                    flag_buf,
                    len(tokens),
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        out = self._ffi.new("uint32_t[]", needed)
        try:
            written = int(
                self._lib.turbotoken_filter_tokens_by_keep_flags(
                    token_buf,
                    flag_buf,
                    len(tokens),
                    out,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def count_bpe_from_ranks(self, rank_payload: bytes, data: bytes) -> int | None:
        self.load()
        if self._lib is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        try:
            result = int(
                self._lib.turbotoken_count_bpe_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    data,
                    len(data),
                )
            )
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def count_bpe_ascii_o200k_from_ranks(self, rank_payload: bytes, data: bytes) -> int | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            result = int(
                self._lib.turbotoken_count_bpe_ascii_o200k_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                )
            )
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def encode_bpe_ascii_o200k_from_ranks(self, rank_payload: bytes, data: bytes) -> list[int] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            needed = int(
                self._lib.turbotoken_encode_bpe_ascii_o200k_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        try:
            out = self._ffi.new("uint32_t[]", needed)
            written = int(
                self._lib.turbotoken_encode_bpe_ascii_o200k_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    out,
                    needed,
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def decode_bpe_from_ranks(self, rank_payload: bytes, tokens: list[int]) -> bytes | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        token_buf = self._ffi.new("uint32_t[]", tokens)
        try:
            needed = int(
                self._lib.turbotoken_decode_bpe_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    token_buf,
                    len(tokens),
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return b""

        out = self._ffi.new("unsigned char[]", needed)
        try:
            written = int(
                self._lib.turbotoken_decode_bpe_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    token_buf,
                    len(tokens),
                    out,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return bytes(self._ffi.buffer(out, written))


@lru_cache(maxsize=1)
def get_native_bridge() -> NativeBridge:
    return NativeBridge()
