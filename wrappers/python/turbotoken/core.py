from __future__ import annotations

import os
import platform
import re
from functools import lru_cache
from typing import TYPE_CHECKING, Any, AbstractSet, Callable, Collection, Iterable, Literal, Mapping, TypeVar

from ._rank_files import (
    ensure_rank_file,
    load_decoder_only,
    load_piece_bpe_cache,
    load_ranks_only,
    read_rank_file_native_payload,
    rank_file_path,
    save_piece_bpe_cache,
)
from ._registry import EncodingSpec, get_encoding_spec
from ._registry import list_encoding_names as _list_encoding_names
from ._registry import model_to_encoding

AllowedSpecial = Literal["all"] | AbstractSet[str]
DisallowedSpecial = Literal["all"] | Collection[str]
T = TypeVar("T")
U = TypeVar("U")

if TYPE_CHECKING:
    from pathlib import Path


_O200K_ASCII_PAT_STR = "|".join(
    [
        r"""[^\r\nA-Za-z0-9]?[A-Z]*[a-z]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?""",
        r"""[^\r\nA-Za-z0-9]?[A-Z]+[a-z]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?""",
        r"""\d{1,3}""",
        r""" ?[^\sA-Za-z0-9]+[\r\n/]*""",
        r"""\s*[\r\n]+""",
        r"""\s+(?!\S)""",
        r"""\s+""",
    ]
)

_CL100K_ASCII_PAT_STR = (
    r"""'(?i:[sdmt]|ll|ve|re)|[^\r\nA-Za-z0-9]?[A-Za-z]+|\d{1,3}| ?[^\sA-Za-z0-9]+[\r\n]*|\s+$|\s*[\r\n]|\s+(?!\S)|\s+"""
)
_O200K_ASCII_PAT_BYTES = _O200K_ASCII_PAT_STR.encode("ascii")
_CL100K_ASCII_PAT_BYTES = _CL100K_ASCII_PAT_STR.encode("ascii")
_CHAT_START = "<|im_start|>"
_CHAT_END = "<|im_end|>"
_CHAT_TEMPLATE_TURBOTOKEN_V1 = "turbotoken_v1"
_CHAT_TEMPLATE_IM_TOKENS = "im_tokens"


@lru_cache(maxsize=1)
def _gpu_module() -> Any:
    from . import _gpu as gpu_module

    return gpu_module


@lru_cache(maxsize=1)
def _native_bridge() -> Any:
    from ._native import get_native_bridge

    return get_native_bridge()


@lru_cache(maxsize=4)
def _compile_ascii_piece_regex(pattern: str) -> re.Pattern[str]:
    return re.compile(pattern)


@lru_cache(maxsize=4)
def _compile_ascii_piece_regex_bytes(pattern: bytes) -> re.Pattern[bytes]:
    return re.compile(pattern)


def _sanitize_text(text: str) -> str:
    # Match tiktoken's surrogate handling so encode/decode stay resilient on odd input.
    return text.encode("utf-16", "surrogatepass").decode("utf-16", "replace")


def _is_linux_x86_64_host() -> bool:
    if platform.system().lower() != "linux":
        return False
    return platform.machine().lower() in {"x86_64", "amd64"}


def _utf8_len_fast(text: str) -> int:
    # Fast path for ASCII workloads: UTF-8 length equals codepoint length.
    if text.isascii():
        return len(text)
    return len(text.encode("utf-8"))


def _gpu_short_lane_bypass_enabled() -> bool:
    raw = os.environ.get("TURBOTOKEN_GPU_SHORT_LANE_BYPASS_ENABLE", "").strip().lower()
    if raw in {"0", "false", "no", "off"}:
        return False
    if raw in {"1", "true", "yes", "on"}:
        return True
    return True


@lru_cache(maxsize=128)
def _special_token_regex(tokens: frozenset[str]):
    import regex

    if not tokens:
        return regex.compile(r"(?!x)x")

    pattern = "|".join(regex.escape(token) for token in sorted(tokens, key=len, reverse=True))
    return regex.compile(pattern)


class Encoding:
    __slots__ = (
        "name",
        "_spec",
        "_mergeable_ranks_cache",
        "_decoder",
        "_token_byte_values_cache",
        "_piece_regex",
        "_bpe_cache",
        "_ascii_text_bpe_cache",
        "_rank_payload_cache",
        "_persistent_piece_cache",
        "_merge_cache_size",
        "_native_rank_session_cache",
        "_native_rank_payload_ref",
    )

    name: str
    _spec: EncodingSpec
    _mergeable_ranks_cache: dict[bytes, int] | None
    _decoder: dict[int, bytes] | None
    _token_byte_values_cache: list[bytes] | None
    _piece_regex: Any | None
    _bpe_cache: dict[bytes, tuple[int, ...]]
    _ascii_text_bpe_cache: dict[str, tuple[int, ...]]
    _rank_payload_cache: bytes | None
    _persistent_piece_cache: dict[bytes, tuple[int, ...]] | None
    _merge_cache_size: int
    _native_rank_session_cache: Any | None
    _native_rank_payload_ref: bytes | None

    def __init__(
        self,
        name: str,
        *,
        _spec: EncodingSpec | None = None,
        pat_str: str | None = None,
        mergeable_ranks: dict[bytes, int] | None = None,
        special_tokens: dict[str, int] | None = None,
    ) -> None:
        self.name = name
        self._decoder = None
        self._token_byte_values_cache = None
        self._piece_regex = None
        self._bpe_cache = {}
        self._ascii_text_bpe_cache = {}
        self._rank_payload_cache = None
        self._persistent_piece_cache = None
        self._merge_cache_size = self._default_merge_cache_size()
        self._native_rank_session_cache = None
        self._native_rank_payload_ref = None

        if _spec is not None:
            self._spec = _spec
            self._mergeable_ranks_cache = None
            return

        if pat_str is None or mergeable_ranks is None or special_tokens is None:
            raise TypeError(
                "Encoding() requires either _spec=... or "
                "pat_str=..., mergeable_ranks=..., special_tokens=..."
            )

        mergeable = dict(mergeable_ranks)
        specials = dict(special_tokens)

        max_token = -1
        if mergeable:
            max_token = max(max_token, max(mergeable.values()))
        if specials:
            max_token = max(max_token, max(specials.values()))

        self._spec = EncodingSpec(
            name=name,
            rank_file_url="",
            pat_str=pat_str,
            special_tokens=specials,
            explicit_n_vocab=max_token + 1,
        )
        self._mergeable_ranks_cache = mergeable

    @staticmethod
    def _default_merge_cache_size() -> int:
        raw = os.environ.get("TURBOTOKEN_MERGE_CACHE_SIZE", "").strip()
        if not raw:
            return 100_000
        try:
            parsed = int(raw)
        except ValueError:
            return 100_000
        return max(0, parsed)

    def _cache_room(self, current_size: int) -> bool:
        return self._merge_cache_size > 0 and current_size < self._merge_cache_size

    def set_merge_cache_size(self, size: int) -> None:
        if size < 0:
            raise ValueError("merge cache size must be >= 0")
        self._merge_cache_size = size
        if size == 0:
            self.clear_merge_cache()
            return
        if len(self._bpe_cache) > size:
            self._bpe_cache.clear()
        if len(self._ascii_text_bpe_cache) > size:
            self._ascii_text_bpe_cache.clear()

    def clear_merge_cache(self) -> None:
        self._bpe_cache.clear()
        self._ascii_text_bpe_cache.clear()
        self._native_rank_session_cache = None
        self._native_rank_payload_ref = None
        bridge = _native_bridge()
        clear_native = getattr(bridge, "clear_rank_table_cache", None)
        if callable(clear_native):
            clear_native()

    @property
    def n_vocab(self) -> int:
        return self._spec.n_vocab

    @property
    def max_token_value(self) -> int:
        return self.n_vocab - 1

    @property
    def eot_token(self) -> int:
        return self._spec.eot_token

    @property
    def _pat_str(self) -> str:
        return self._spec.pat_str

    @property
    def _special_tokens(self) -> dict[str, int]:
        return dict(self._spec.special_tokens)

    @property
    def _mergeable_ranks(self) -> dict[bytes, int]:
        return self.load_mergeable_ranks()

    @property
    def special_tokens_set(self) -> set[str]:
        return set(self._spec.special_tokens.keys())

    def _allowed_special_set(self, allowed_special: AllowedSpecial) -> set[str]:
        if allowed_special == "all":
            return set(self._spec.special_tokens.keys())
        return set(allowed_special)

    def _disallowed_special_set(self, disallowed_special: DisallowedSpecial) -> set[str]:
        if disallowed_special == "all":
            return set(self._spec.special_tokens.keys())
        return set(disallowed_special)

    def _special_token_to_id(self, token: str) -> int:
        try:
            return self._spec.special_tokens[token]
        except KeyError as exc:
            raise KeyError(f"Unknown special token: {token!r}") from exc

    def _raise_if_disallowed_special(self, text: str, disallowed_special: set[str]) -> None:
        if not disallowed_special:
            return
        start_chars = {token[0] for token in disallowed_special if token}
        if start_chars and all(ch not in text for ch in start_chars):
            return
        if match := _special_token_regex(frozenset(disallowed_special)).search(text):
            token = match.group()
            raise ValueError(
                f"Encountered text corresponding to disallowed special token {token!r}. "
                "Pass this token in allowed_special, or set disallowed_special=() to encode it as ordinary text."
            )

    def _ensure_piece_regex(self) -> Any:
        if self._piece_regex is None:
            import regex

            self._piece_regex = regex.compile(self._spec.pat_str)
        return self._piece_regex

    def _ascii_piece_regex(self) -> re.Pattern[str] | None:
        if os.environ.get("TURBOTOKEN_ASCII_REGEX_FASTPATH_DISABLE", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }:
            return None
        if self.name in {"o200k_base", "o200k_harmony"}:
            return _compile_ascii_piece_regex(_O200K_ASCII_PAT_STR)
        if self.name == "cl100k_base":
            return _compile_ascii_piece_regex(_CL100K_ASCII_PAT_STR)
        return None

    def _ascii_piece_regex_bytes(self) -> re.Pattern[bytes] | None:
        if os.environ.get("TURBOTOKEN_ASCII_REGEX_FASTPATH_DISABLE", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }:
            return None
        if self.name in {"o200k_base", "o200k_harmony"}:
            return _compile_ascii_piece_regex_bytes(_O200K_ASCII_PAT_BYTES)
        if self.name == "cl100k_base":
            return _compile_ascii_piece_regex_bytes(_CL100K_ASCII_PAT_BYTES)
        return None

    def _native_ascii_letter_space_ranges(
        self,
        text: str,
    ) -> tuple[bytes, list[tuple[int, int]]] | None:
        if os.environ.get("TURBOTOKEN_NATIVE_PRETOKENIZER_ENABLE", "").strip().lower() not in {
            "1",
            "true",
            "yes",
        }:
            return None
        if os.environ.get("TURBOTOKEN_NATIVE_PRETOKENIZER_DISABLE", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }:
            return None
        if self.name not in {"cl100k_base", "o200k_base"}:
            return None
        if len(text) < 2048 or not text.isascii():
            return None

        data = text.encode("ascii")
        for byte in data:
            if byte == 0x20:
                continue
            if 65 <= byte <= 90:
                continue
            if 97 <= byte <= 122:
                continue
            return None

        bridge = _native_bridge()
        if not bridge.available:
            return None
        ranges = bridge.pretokenize_ascii_letter_space_ranges(data)
        if ranges is None:
            return None

        for start, end in ranges:
            if start < 0 or end < start or end > len(data):
                return None
        return data, ranges

    def _native_ascii_letter_space_piece_bytes(self, text: str) -> list[bytes] | None:
        native = self._native_ascii_letter_space_ranges(text)
        if native is None:
            return None
        data, ranges = native
        pieces: list[bytes] = []
        for start, end in ranges:
            if start == end:
                continue
            pieces.append(data[start:end])
        return pieces

    def _native_ascii_o200k_ranges(
        self,
        text: str,
    ) -> tuple[bytes, list[tuple[int, int]]] | None:
        if os.environ.get("TURBOTOKEN_NATIVE_O200K_PRETOKENIZER_DISABLE", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }:
            return None
        if self.name not in {"o200k_base", "o200k_harmony"}:
            return None
        if len(text) < 1024 or not text.isascii():
            return None

        explicit_enable = os.environ.get("TURBOTOKEN_NATIVE_O200K_PRETOKENIZER_ENABLE", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }
        # Auto-enable for large ASCII payloads where pretokenization cost dominates.
        if not explicit_enable and len(text) < 65_536:
            return None

        data = text.encode("ascii")
        for byte in data:
            if byte == 127:
                return None
            if byte < 32 and byte not in {10, 13}:
                return None

        bridge = _native_bridge()
        if not bridge.available:
            return None
        ranges = bridge.pretokenize_ascii_o200k_ranges(data)
        if ranges is None:
            return None

        for start, end in ranges:
            if start < 0 or end < start or end > len(data):
                return None
        return data, ranges

    def _native_ascii_o200k_piece_bytes(self, text: str) -> list[bytes] | None:
        native = self._native_ascii_o200k_ranges(text)
        if native is None:
            return None
        data, ranges = native
        pieces: list[bytes] = []
        for start, end in ranges:
            if start == end:
                continue
            pieces.append(data[start:end])
        return pieces

    def _native_pretokenized_ranges(self, text: str) -> tuple[bytes, list[tuple[int, int]]] | None:
        native_o200k = self._native_ascii_o200k_ranges(text)
        if native_o200k is not None:
            return native_o200k
        return self._native_ascii_letter_space_ranges(text)

    def _encode_ordinary_native_ranges(self, text: str) -> list[int] | None:
        if os.environ.get("TURBOTOKEN_NATIVE_RANGE_BATCH_DISABLE", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }:
            return None
        force_enable = os.environ.get("TURBOTOKEN_NATIVE_RANGE_BATCH_ENABLE", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }
        if not force_enable and not self._native_range_batch_auto_enabled(text):
            return None

        piece_ranges = self._ordinary_piece_ranges_bytes(text)
        if piece_ranges is None:
            return None
        data, ranges = piece_ranges
        if not ranges:
            return []
        session = self._native_rank_session()
        if session is None:
            return None

        if len(ranges) == 1:
            single = session.encode_bpe(data)
            if single is not None:
                return single

        batch = session.encode_bpe_ranges(data, ranges)
        if batch is None:
            return None
        tokens, _ = batch
        return tokens

    def _count_ordinary_native_ranges(self, text: str) -> int | None:
        if os.environ.get("TURBOTOKEN_NATIVE_RANGE_BATCH_DISABLE", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }:
            return None
        force_enable = os.environ.get("TURBOTOKEN_NATIVE_RANGE_BATCH_ENABLE", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }
        if not force_enable and not self._native_range_batch_auto_enabled(text):
            return None

        piece_ranges = self._ordinary_piece_ranges_bytes(text)
        if piece_ranges is None:
            return None
        data, ranges = piece_ranges
        if not ranges:
            return 0
        session = self._native_rank_session()
        if session is None:
            return None
        if len(ranges) == 1:
            return session.count_bpe(data)
        return session.count_bpe_ranges(data, ranges)

    def _ordinary_piece_bytes_iter(self, text: str) -> Iterable[bytes]:
        native_o200k_pieces = self._native_ascii_o200k_piece_bytes(text)
        if native_o200k_pieces is not None:
            for piece in native_o200k_pieces:
                yield piece
            return

        native_pieces = self._native_ascii_letter_space_piece_bytes(text)
        if native_pieces is not None:
            for piece in native_pieces:
                yield piece
            return

        if text.isascii():
            ascii_regex_bytes = self._ascii_piece_regex_bytes()
            if ascii_regex_bytes is not None:
                data = text.encode("ascii")
                for match in ascii_regex_bytes.finditer(data):
                    piece = match.group(0)
                    if piece:
                        yield piece
                return

            ascii_regex = self._ascii_piece_regex()
            if ascii_regex is not None:
                for match in ascii_regex.finditer(text):
                    piece = match.group(0)
                    if piece:
                        yield piece.encode("ascii")
                return

        piece_regex = self._ensure_piece_regex()
        for match in piece_regex.finditer(text):
            piece = match.group(0)
            if not piece:
                continue
            yield piece.encode("utf-8")

    def _ordinary_piece_bytes(self, text: str) -> list[bytes]:
        return list(self._ordinary_piece_bytes_iter(text))

    def _ordinary_piece_bytes_pipelined_iter(self, text: str, *, max_prefetch: int) -> Iterable[bytes]:
        from queue import SimpleQueue
        from threading import Thread

        _ = max_prefetch
        sentinel = object()
        queue: SimpleQueue[bytes | object] = SimpleQueue()
        errors: list[BaseException] = []

        def _producer() -> None:
            try:
                for piece in self._ordinary_piece_bytes_iter(text):
                    queue.put(piece)
            except BaseException as exc:  # pragma: no cover - rethrown on consumer side
                errors.append(exc)
            finally:
                queue.put(sentinel)

        producer = Thread(target=_producer, name="turbotoken-gpu-overlap-pretokenize", daemon=True)
        producer.start()
        try:
            while True:
                item = queue.get()
                if item is sentinel:
                    break
                yield item  # type: ignore[misc]
            if errors:
                raise errors[0]
        finally:
            producer.join()

    def _ordinary_piece_ranges_bytes(self, text: str) -> tuple[bytes, list[tuple[int, int]]] | None:
        native_ranges = self._native_pretokenized_ranges(text)
        if native_ranges is not None:
            return native_ranges

        pieces = self._ordinary_piece_bytes(text)
        if not pieces:
            return b"", []

        data = b"".join(pieces)
        ranges: list[tuple[int, int]] = []
        cursor = 0
        for piece in pieces:
            next_cursor = cursor + len(piece)
            ranges.append((cursor, next_cursor))
            cursor = next_cursor
        return data, ranges

    def _ensure_rank_payload(self, *, cache_dir: "Path | None" = None, force: bool = False) -> bytes:
        if self._rank_payload_cache is not None and not force:
            return self._rank_payload_cache

        native_payload_disable = os.environ.get("TURBOTOKEN_NATIVE_RANK_PAYLOAD_DISABLE", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }
        if native_payload_disable:
            rank_path = ensure_rank_file(self.name, dir_path=cache_dir, force=force)
            payload = rank_path.read_bytes()
        else:
            payload = read_rank_file_native_payload(self.name, dir_path=cache_dir, force=force)
        self._rank_payload_cache = payload
        self._native_rank_session_cache = None
        self._native_rank_payload_ref = None
        return self._rank_payload_cache

    def _native_piece_min_bytes(self) -> int:
        raw = os.environ.get("TURBOTOKEN_NATIVE_PIECE_MIN_BYTES", "").strip()
        if not raw:
            return 2048
        try:
            value = int(raw, 10)
        except ValueError:
            return 2048
        return max(1, value)

    def _native_cl100k_full_min_bytes(self) -> int:
        raw = os.environ.get("TURBOTOKEN_NATIVE_CL100K_FULL_MIN_BYTES", "").strip()
        if not raw:
            return 131_072
        try:
            value = int(raw, 10)
        except ValueError:
            return 131_072
        return max(1, value)

    def _native_o200k_full_min_bytes(self) -> int:
        raw = os.environ.get("TURBOTOKEN_NATIVE_O200K_FULL_MIN_BYTES", "").strip()
        if not raw:
            return 65_536
        try:
            value = int(raw, 10)
        except ValueError:
            return 65_536
        return max(1, value)

    def _native_o200k_large_ascii_auto_enabled(self, text: str) -> bool:
        if self.name not in {"o200k_base", "o200k_harmony"}:
            return False
        if not text.isascii():
            return False
        if _utf8_len_fast(text) < self._native_o200k_full_min_bytes():
            return False
        # Keep large-text o200k full/range routing opt-in until hosted x64 data
        # consistently beats the default cached CPU path.
        return False

    def _native_o200k_full_auto_enabled(self, text: str) -> bool:
        return self._native_o200k_large_ascii_auto_enabled(text)

    def _native_range_batch_auto_enabled(self, text: str) -> bool:
        return self._native_o200k_large_ascii_auto_enabled(text)

    def _native_decode_min_tokens(self) -> int:
        raw = os.environ.get("TURBOTOKEN_NATIVE_DECODE_MIN_TOKENS", "").strip()
        if not raw:
            return 512
        try:
            value = int(raw, 10)
        except ValueError:
            return 512
        return max(1, value)

    def _gpu_overlap_enabled(self) -> bool:
        raw = os.environ.get("TURBOTOKEN_GPU_OVERLAP_ENABLE", "").strip().lower()
        if raw in {"0", "false", "no", "off"}:
            return False
        if raw in {"1", "true", "yes", "on"}:
            return True
        return True

    def _gpu_overlap_min_text_bytes(self) -> int:
        raw = os.environ.get("TURBOTOKEN_GPU_OVERLAP_MIN_TEXT_BYTES", "").strip()
        if not raw:
            return 262_144
        try:
            value = int(raw, 10)
        except ValueError:
            return 262_144
        return max(1, value)

    def _gpu_overlap_prefetch_pieces(self) -> int:
        raw = os.environ.get("TURBOTOKEN_GPU_OVERLAP_PREFETCH_PIECES", "").strip()
        if not raw:
            return 32
        try:
            value = int(raw, 10)
        except ValueError:
            return 32
        return max(2, value)

    def _gpu_range_batch_enabled(self) -> bool:
        raw = os.environ.get("TURBOTOKEN_GPU_RANGE_BATCH_ENABLE", "").strip().lower()
        if raw in {"0", "false", "no", "off"}:
            return False
        if raw in {"1", "true", "yes", "on"}:
            return True
        return True

    def _gpu_range_batch_min_text_bytes(self) -> int:
        raw = os.environ.get("TURBOTOKEN_GPU_RANGE_BATCH_MIN_TEXT_BYTES", "").strip()
        if not raw:
            return 262_144
        try:
            value = int(raw, 10)
        except ValueError:
            return 262_144
        return max(1, value)

    def _gpu_range_batch_min_metal_pieces(self) -> int:
        raw = os.environ.get("TURBOTOKEN_GPU_RANGE_BATCH_MIN_METAL_PIECES", "").strip()
        if not raw:
            return 2
        try:
            value = int(raw, 10)
        except ValueError:
            return 2
        return max(1, value)

    def _gpu_range_batch_max_ranges(self) -> int:
        raw = os.environ.get("TURBOTOKEN_GPU_RANGE_BATCH_MAX_RANGES", "").strip()
        if not raw:
            return 8192
        try:
            value = int(raw, 10)
        except ValueError:
            return 8192
        return max(1, value)

    def _metal_force_all_cpu_fallback_max_ranges(self) -> int:
        raw = os.environ.get("TURBOTOKEN_METAL_FORCE_ALL_CPU_FALLBACK_MAX_RANGES", "").strip()
        if not raw:
            return 128
        try:
            value = int(raw, 10)
        except ValueError:
            return 128
        return max(0, value)

    def _native_rank_session(self) -> Any | None:
        rank_payload = self._rank_payload_cache
        if rank_payload is None:
            rank_payload = self._ensure_rank_payload()

        if (
            self._native_rank_session_cache is not None
            and self._native_rank_payload_ref is rank_payload
        ):
            return self._native_rank_session_cache

        bridge = _native_bridge()
        if not bridge.available:
            return None
        session = bridge.rank_session(rank_payload)
        if session is None:
            return None
        self._native_rank_session_cache = session
        self._native_rank_payload_ref = rank_payload
        return session

    def _bpe_tokenize_piece(self, piece: bytes) -> tuple[int, ...]:
        if not piece:
            return ()

        cached = self._bpe_cache.get(piece)
        if cached is not None:
            return cached

        mergeable_ranks = self.load_mergeable_ranks()
        direct_token = mergeable_ranks.get(piece)
        if direct_token is not None:
            result = (direct_token,)
            if self._cache_room(len(self._bpe_cache)):
                self._bpe_cache[piece] = result
            return result

        # Large repeated segments are expensive in pure-Python BPE; use native Zig path when available.
        native_piece_min_bytes = self._native_piece_min_bytes()
        if len(piece) >= native_piece_min_bytes:
            session = self._native_rank_session()
            native_tokens = session.encode_bpe(piece) if session is not None else None
            if native_tokens is not None:
                result = tuple(native_tokens)
                if self._cache_room(len(self._bpe_cache)):
                    self._bpe_cache[piece] = result
                return result

        parts = [bytes([byte]) for byte in piece]
        while len(parts) > 1:
            best_idx = -1
            best_rank: int | None = None
            for idx in range(len(parts) - 1):
                rank = mergeable_ranks.get(parts[idx] + parts[idx + 1])
                if rank is None:
                    continue
                if best_rank is None or rank < best_rank:
                    best_rank = rank
                    best_idx = idx
            if best_idx < 0:
                break
            parts = parts[:best_idx] + [parts[best_idx] + parts[best_idx + 1]] + parts[best_idx + 2 :]

        result = tuple(mergeable_ranks[part] for part in parts)
        if self._cache_room(len(self._bpe_cache)):
            self._bpe_cache[piece] = result
        return result

    def _ensure_persistent_piece_cache(self) -> None:
        if self._persistent_piece_cache is not None:
            return

        if os.environ.get("TURBOTOKEN_PERSISTENT_PIECE_CACHE_DISABLE", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }:
            self._persistent_piece_cache = {}
            return
        if not self._spec.rank_file_url:
            self._persistent_piece_cache = {}
            return

        pieces = load_piece_bpe_cache(self.name)
        self._persistent_piece_cache = pieces
        if not pieces:
            return

        for piece_bytes, piece_tokens in pieces.items():
            if self._cache_room(len(self._bpe_cache)) and piece_bytes not in self._bpe_cache:
                self._bpe_cache[piece_bytes] = piece_tokens
            try:
                piece_text = piece_bytes.decode("ascii")
            except UnicodeDecodeError:
                continue
            if self._cache_room(len(self._ascii_text_bpe_cache)) and piece_text not in self._ascii_text_bpe_cache:
                self._ascii_text_bpe_cache[piece_text] = piece_tokens

    def _persist_piece_entries(self, entries: dict[bytes, tuple[int, ...]]) -> None:
        if not entries:
            return
        if not self._spec.rank_file_url:
            return
        self._ensure_persistent_piece_cache()
        assert self._persistent_piece_cache is not None

        changed = False
        for piece_bytes, piece_tokens in entries.items():
            if piece_bytes in self._persistent_piece_cache:
                continue
            self._persistent_piece_cache[piece_bytes] = piece_tokens
            changed = True
        if not changed:
            return

        if len(self._persistent_piece_cache) > 50_000:
            return
        save_piece_bpe_cache(self.name, self._persistent_piece_cache)

    def _encode_bytes(self, data: bytes) -> list[int]:
        if not data:
            return []
        return list(self._bpe_tokenize_piece(data))

    def _encode_ordinary_impl(self, text: str) -> list[int]:
        if not text:
            return []
        if (
            self.name == "cl100k_base"
            and text.isascii()
            and os.environ.get("TURBOTOKEN_NATIVE_CL100K_FULL_ENABLE", "").strip().lower() in {"1", "true", "yes"}
            and os.environ.get("TURBOTOKEN_NATIVE_CL100K_FULL_DISABLE", "").strip().lower()
            not in {"1", "true", "yes"}
            and len(text) >= self._native_cl100k_full_min_bytes()
        ):
            session = self._native_rank_session()
            if session is not None:
                native_tokens = session.encode_bpe_ascii_letter_space(text.encode("ascii"))
                if native_tokens is not None:
                    return native_tokens
        if (
            self.name in {"o200k_base", "o200k_harmony"}
            and text.isascii()
            and (
                os.environ.get("TURBOTOKEN_NATIVE_O200K_FULL_ENABLE", "").strip().lower() in {"1", "true", "yes"}
                or self._native_o200k_full_auto_enabled(text)
            )
            and os.environ.get("TURBOTOKEN_NATIVE_O200K_FULL_DISABLE", "").strip().lower()
            not in {"1", "true", "yes"}
        ):
            session = self._native_rank_session()
            if session is not None:
                native_tokens = session.encode_bpe_ascii_o200k(text.encode("ascii"))
                if native_tokens is not None:
                    return native_tokens

        native_range_tokens = self._encode_ordinary_native_ranges(text)
        if native_range_tokens is not None:
            return native_range_tokens

        if text.isascii():
            ascii_regex = self._ascii_piece_regex()
            if ascii_regex is not None:
                return self._encode_ordinary_ascii_impl(text, ascii_regex)
        bpe_cache = self._bpe_cache
        out: list[int] = []
        last_piece: bytes | None = None
        last_tokens: tuple[int, ...] = ()
        for piece_bytes in self._ordinary_piece_bytes(text):
            if piece_bytes == last_piece:
                out.extend(last_tokens)
                continue

            cached = bpe_cache.get(piece_bytes)
            if cached is None:
                cached = self._bpe_tokenize_piece(piece_bytes)

            out.extend(cached)
            last_piece = piece_bytes
            last_tokens = cached
        return out

    def _encode_ordinary_ascii_impl(self, text: str, ascii_regex: re.Pattern[str]) -> list[int]:
        bpe_cache = self._bpe_cache
        ascii_cache = self._ascii_text_bpe_cache
        if len(text) >= 8192:
            self._ensure_persistent_piece_cache()
        pieces = [piece for piece in ascii_regex.findall(text) if piece]
        if not pieces:
            return []
        new_persistent_entries: dict[bytes, tuple[int, ...]] = {}

        if len(pieces) >= 4096:
            unique_pieces = set(pieces)
            if len(unique_pieces) * 4 <= len(pieces):
                import itertools

                unique_token_map: dict[str, tuple[int, ...]] = {}
                for piece_text in unique_pieces:
                    cached = ascii_cache.get(piece_text)
                    if cached is None:
                        piece_bytes = piece_text.encode("ascii")
                        cached = bpe_cache.get(piece_bytes)
                        if cached is None:
                            cached = self._bpe_tokenize_piece(piece_bytes)
                            if len(piece_bytes) <= 64:
                                new_persistent_entries[piece_bytes] = cached
                        if self._cache_room(len(ascii_cache)):
                            ascii_cache[piece_text] = cached
                    unique_token_map[piece_text] = cached
                out = list(itertools.chain.from_iterable(unique_token_map[piece] for piece in pieces))
                if new_persistent_entries:
                    self._persist_piece_entries(new_persistent_entries)
                return out

        out: list[int] = []
        last_piece: str | None = None
        last_tokens: tuple[int, ...] = ()
        for piece_text in pieces:
            if piece_text == last_piece:
                out.extend(last_tokens)
                continue

            cached = ascii_cache.get(piece_text)
            if cached is None:
                piece_bytes = piece_text.encode("ascii")
                cached = bpe_cache.get(piece_bytes)
                if cached is None:
                    cached = self._bpe_tokenize_piece(piece_bytes)
                    if len(piece_bytes) <= 64:
                        new_persistent_entries[piece_bytes] = cached
                if self._cache_room(len(ascii_cache)):
                    ascii_cache[piece_text] = cached

            out.extend(cached)
            last_piece = piece_text
            last_tokens = cached
        if new_persistent_entries:
            self._persist_piece_entries(new_persistent_entries)
        return out

    def _encode_ordinary_gpu_impl(
        self,
        text: str,
        *,
        device: str,
        chunk_bytes: int,
        overlap_bytes: int,
        strict_verify: bool,
    ) -> list[int]:
        if not text:
            return []

        self.load_mergeable_ranks()
        rank_payload = self._rank_payload_cache
        if rank_payload is None:
            rank_payload = self._ensure_rank_payload()
        session = self._native_rank_session() if rank_payload is not None else None
        gpu = None
        if device in {"auto", "metal"}:
            try:
                gpu = _gpu_module()
            except Exception:
                gpu = None
        bpe_cache = self._bpe_cache
        text_bytes_len = _utf8_len_fast(text)
        use_overlap_pretokenize = (
            gpu is not None
            and not strict_verify
            and self._gpu_overlap_enabled()
            and text_bytes_len >= self._gpu_overlap_min_text_bytes()
        )

        use_gpu_range_batch = (
            gpu is not None
            and session is not None
            and rank_payload is not None
            and not strict_verify
            and self._gpu_range_batch_enabled()
            and text_bytes_len >= self._gpu_range_batch_min_text_bytes()
        )
        force_all_metal = os.environ.get("TURBOTOKEN_METAL_FORCE_ALL_PIECES", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }
        force_all_metal_strict = os.environ.get("TURBOTOKEN_METAL_FORCE_ALL_PIECES_STRICT", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }
        if (
            device == "metal"
            and gpu is not None
            and not strict_verify
            and _gpu_short_lane_bypass_enabled()
            and not force_all_metal_strict
        ):
            # Strict short-lane policy: below direct-size crossover, stay on CPU/native.
            # This avoids paying Metal setup/route overhead on known short-text regimes.
            try:
                direct_min = int(gpu._metal_bpe_direct_min_bytes())  # type: ignore[attr-defined]
            except Exception:
                direct_min = 262_144
            if text_bytes_len < max(1, direct_min):
                return self._encode_ordinary_impl(text)
        if (
            device in {"auto", "metal"}
            and force_all_metal
            and not force_all_metal_strict
            and gpu is not None
            and not strict_verify
        ):
            # Guard force-all mode on sub-direct-size texts; otherwise thousands of
            # tiny regex pieces can be slower than the regular CPU path.
            try:
                direct_min = int(gpu._metal_bpe_direct_min_bytes())  # type: ignore[attr-defined]
            except Exception:
                direct_min = 262_144
            if text_bytes_len < max(1, direct_min):
                return self._encode_ordinary_impl(text)
            fallback_max_ranges = self._metal_force_all_cpu_fallback_max_ranges()
            if fallback_max_ranges > 0:
                piece_ranges = self._ordinary_piece_ranges_bytes(text)
                if piece_ranges is not None:
                    _, ranges = piece_ranges
                    if len(ranges) > fallback_max_ranges:
                        return self._encode_ordinary_impl(text)

        if device == "auto" and gpu is not None and not strict_verify:
            # When autoroute is CPU for this text, delegate to the regular encode path.
            # This keeps cache-friendly CPU behavior and avoids GPU-routing overhead.
            if gpu.bpe_route_backend(text_bytes_len) != "metal":
                return self._encode_ordinary_impl(text)

        if use_gpu_range_batch:
            piece_ranges = self._ordinary_piece_ranges_bytes(text)
            if piece_ranges is not None:
                data, ranges = piece_ranges
                if not ranges:
                    return []
                max_ranges = self._gpu_range_batch_max_ranges()
                if len(ranges) > max_ranges:
                    # Keep large-piece-count inputs on native range batching in chunks.
                    # This avoids an expensive fallback to per-piece Python BPE.
                    cpu_tokens: list[int] = []
                    cpu_chunk_ok = True
                    for range_start in range(0, len(ranges), max_ranges):
                        sub_ranges = ranges[range_start : range_start + max_ranges]
                        cpu_batch = session.encode_bpe_ranges(data, sub_ranges)
                        if cpu_batch is None:
                            cpu_chunk_ok = False
                            break
                        flat_tokens, token_offsets = cpu_batch
                        if len(token_offsets) != len(sub_ranges) + 1:
                            cpu_chunk_ok = False
                            break
                        if flat_tokens:
                            cpu_tokens.extend(flat_tokens)
                    if cpu_chunk_ok:
                        return cpu_tokens
                    ranges = []

                cpu_indices: list[int] = []
                cpu_ranges: list[tuple[int, int]] = []
                metal_indices: list[int] = []
                metal_ranges: list[tuple[int, int]] = []

                for idx, (start, end) in enumerate(ranges):
                    piece_len = end - start
                    if piece_len <= 0:
                        continue
                    if force_all_metal:
                        route_backend = "metal"
                    else:
                        route_backend = gpu.bpe_route_backend(piece_len)
                    if route_backend == "metal" and (force_all_metal or piece_len >= (chunk_bytes * 2)):
                        metal_indices.append(idx)
                        metal_ranges.append((start, end))
                    else:
                        cpu_indices.append(idx)
                        cpu_ranges.append((start, end))

                min_metal_ranges = 1 if force_all_metal else self._gpu_range_batch_min_metal_pieces()
                if not metal_ranges or len(metal_ranges) < min_metal_ranges:
                    # If Metal does not qualify for this text, keep the fast native
                    # range-batch path instead of falling through to per-piece Python BPE.
                    if cpu_ranges and len(cpu_ranges) == len(ranges):
                        cpu_batch = session.encode_bpe_ranges(data, ranges)
                        if cpu_batch is not None:
                            flat_tokens, token_offsets = cpu_batch
                            if len(token_offsets) == len(ranges) + 1:
                                return flat_tokens

                    ranges = []
                    cpu_indices = []
                    cpu_ranges = []
                    metal_indices = []
                    metal_ranges = []

                tokens_by_piece: list[list[int] | None] = [None] * len(ranges) if ranges else []

                if cpu_ranges:
                    cpu_batch = session.encode_bpe_ranges(data, cpu_ranges)
                    if cpu_batch is None:
                        tokens_by_piece = []
                    else:
                        flat_tokens, token_offsets = cpu_batch
                        if len(token_offsets) != len(cpu_ranges) + 1:
                            tokens_by_piece = []
                        else:
                            for local_idx, piece_idx in enumerate(cpu_indices):
                                token_start = token_offsets[local_idx]
                                token_end = token_offsets[local_idx + 1]
                                if token_start < 0 or token_end < token_start or token_end > len(flat_tokens):
                                    tokens_by_piece = []
                                    break
                                tokens_by_piece[piece_idx] = flat_tokens[token_start:token_end]

                if tokens_by_piece and metal_ranges:
                    metal_batch = gpu.encode_bpe_chunked_stitched_many(
                        rank_payload,
                        data,
                        metal_ranges,
                        chunk_bytes=chunk_bytes,
                        overlap_bytes=overlap_bytes,
                        strict_verify=strict_verify,
                        prefer_metal_stitch=True,
                    )
                    if metal_batch is None:
                        tokens_by_piece = []
                    else:
                        flat_tokens, token_offsets = metal_batch
                        if len(token_offsets) != len(metal_ranges) + 1:
                            tokens_by_piece = []
                        else:
                            for local_idx, piece_idx in enumerate(metal_indices):
                                token_start = token_offsets[local_idx]
                                token_end = token_offsets[local_idx + 1]
                                if token_start < 0 or token_end < token_start or token_end > len(flat_tokens):
                                    tokens_by_piece = []
                                    break
                                tokens_by_piece[piece_idx] = flat_tokens[token_start:token_end]

                if tokens_by_piece and all(piece_tokens is not None for piece_tokens in tokens_by_piece):
                    out: list[int] = []
                    for piece_tokens in tokens_by_piece:
                        if piece_tokens:
                            out.extend(piece_tokens)
                    return out

        if use_overlap_pretokenize:
            piece_iter: Iterable[bytes] = self._ordinary_piece_bytes_pipelined_iter(
                text,
                max_prefetch=self._gpu_overlap_prefetch_pieces(),
            )
        else:
            piece_iter = self._ordinary_piece_bytes(text)

        def _extend_cached(piece: bytes) -> None:
            cached = bpe_cache.get(piece)
            if cached is None:
                cached_tokens = self._bpe_tokenize_piece(piece)
            else:
                cached_tokens = cached
            out.extend(cached_tokens)

        out: list[int] = []
        native_piece_min_bytes = self._native_piece_min_bytes()
        for piece_bytes in piece_iter:
            if rank_payload is None:
                _extend_cached(piece_bytes)
                continue

            if strict_verify:
                # Exact mode: keep the fast single-pass native encode and skip
                # chunked stitch work that would be verified and discarded anyway.
                if len(piece_bytes) >= native_piece_min_bytes and session is not None:
                    native_tokens = session.encode_bpe(piece_bytes)
                    if native_tokens is not None:
                        out.extend(native_tokens)
                        continue
                _extend_cached(piece_bytes)
                continue

            if force_all_metal and gpu is not None:
                route_backend = "metal"
            else:
                route_backend = gpu.bpe_route_backend(len(piece_bytes)) if gpu is not None else "native"
            if route_backend != "metal":
                if len(piece_bytes) >= native_piece_min_bytes and session is not None:
                    native_tokens = session.encode_bpe(piece_bytes)
                    if native_tokens is not None:
                        out.extend(native_tokens)
                        continue
                _extend_cached(piece_bytes)
                continue

            if not force_all_metal and len(piece_bytes) < (chunk_bytes * 2):
                _extend_cached(piece_bytes)
                continue

            if gpu is None:
                _extend_cached(piece_bytes)
                continue

            chunked = gpu.encode_bpe_chunked_stitched(
                rank_payload,
                piece_bytes,
                chunk_bytes=chunk_bytes,
                overlap_bytes=overlap_bytes,
                strict_verify=strict_verify,
                prefer_metal_stitch=True,
            )
            if chunked is None:
                if len(piece_bytes) >= native_piece_min_bytes and session is not None:
                    native_tokens = session.encode_bpe(piece_bytes)
                    if native_tokens is not None:
                        out.extend(native_tokens)
                        continue
                _extend_cached(piece_bytes)
                continue
            out.extend(chunked)

        return out

    def _count_ordinary_impl(self, text: str) -> int:
        if not text:
            return 0
        if (
            self.name == "cl100k_base"
            and text.isascii()
            and os.environ.get("TURBOTOKEN_NATIVE_CL100K_FULL_ENABLE", "").strip().lower() in {"1", "true", "yes"}
            and os.environ.get("TURBOTOKEN_NATIVE_CL100K_FULL_DISABLE", "").strip().lower()
            not in {"1", "true", "yes"}
            and len(text) >= self._native_cl100k_full_min_bytes()
        ):
            session = self._native_rank_session()
            if session is not None:
                native_count = session.count_bpe_ascii_letter_space(text.encode("ascii"))
                if native_count is not None:
                    return native_count
        if (
            self.name in {"o200k_base", "o200k_harmony"}
            and text.isascii()
            and (
                os.environ.get("TURBOTOKEN_NATIVE_O200K_FULL_ENABLE", "").strip().lower() in {"1", "true", "yes"}
                or self._native_o200k_full_auto_enabled(text)
            )
            and os.environ.get("TURBOTOKEN_NATIVE_O200K_FULL_DISABLE", "").strip().lower()
            not in {"1", "true", "yes"}
        ):
            session = self._native_rank_session()
            if session is not None:
                native_count = session.count_bpe_ascii_o200k(text.encode("ascii"))
                if native_count is not None:
                    return native_count

        native_range_count = self._count_ordinary_native_ranges(text)
        if native_range_count is not None:
            return native_range_count

        if text.isascii():
            ascii_regex = self._ascii_piece_regex()
            if ascii_regex is not None:
                return self._count_ordinary_ascii_impl(text, ascii_regex)
        self.load_mergeable_ranks()
        session = self._native_rank_session()
        bpe_cache = self._bpe_cache
        count = 0
        native_piece_min_bytes = self._native_piece_min_bytes()
        last_piece: bytes | None = None
        last_cached_len = 0
        for piece_bytes in self._ordinary_piece_bytes(text):
            if piece_bytes == last_piece:
                count += last_cached_len
                continue

            cached = bpe_cache.get(piece_bytes)
            if cached is not None:
                cached_len = len(cached)
                count += cached_len
                last_piece = piece_bytes
                last_cached_len = cached_len
                continue

            # Keep count() allocation-free for large pieces by using the native scalar fast path.
            if len(piece_bytes) >= native_piece_min_bytes and session is not None:
                native_count = session.count_bpe(piece_bytes)
                if native_count is not None:
                    count += native_count
                    last_piece = piece_bytes
                    last_cached_len = native_count
                    continue

            token_len = len(self._bpe_tokenize_piece(piece_bytes))
            count += token_len
            last_piece = piece_bytes
            last_cached_len = token_len
        return count

    def _count_ordinary_up_to_limit_impl(self, text: str, token_limit: int) -> int | bool:
        if not text:
            return 0

        self.load_mergeable_ranks()
        session = self._native_rank_session()
        bpe_cache = self._bpe_cache
        native_piece_min_bytes = self._native_piece_min_bytes()
        count = 0
        last_piece: bytes | None = None
        last_cached_len = 0

        for piece_bytes in self._ordinary_piece_bytes(text):
            if piece_bytes == last_piece:
                piece_count = last_cached_len
            else:
                cached = bpe_cache.get(piece_bytes)
                if cached is not None:
                    piece_count = len(cached)
                else:
                    piece_count: int | None = None
                    if len(piece_bytes) >= native_piece_min_bytes and session is not None:
                        native_within = session.is_within_token_limit_bpe(piece_bytes, token_limit - count)
                        if native_within is False:
                            return False
                        if isinstance(native_within, int):
                            piece_count = native_within
                    if piece_count is None:
                        piece_count = len(self._bpe_tokenize_piece(piece_bytes))

                last_piece = piece_bytes
                last_cached_len = piece_count

            count += piece_count
            if count > token_limit:
                return False

        return count

    def _count_ordinary_ascii_impl(self, text: str, ascii_regex: re.Pattern[str]) -> int:
        bpe_cache = self._bpe_cache
        ascii_cache = self._ascii_text_bpe_cache
        if len(text) >= 8192:
            self._ensure_persistent_piece_cache()
        pieces = [piece for piece in ascii_regex.findall(text) if piece]
        if not pieces:
            return 0
        new_persistent_entries: dict[bytes, tuple[int, ...]] = {}

        if len(pieces) >= 4096:
            unique_pieces = set(pieces)
            if len(unique_pieces) * 4 <= len(pieces):
                from collections import Counter

                piece_counts = Counter(pieces)
                unique_len_map: dict[str, int] = {}
                for piece_text in unique_pieces:
                    cached = ascii_cache.get(piece_text)
                    if cached is None:
                        piece_bytes = piece_text.encode("ascii")
                        cached = bpe_cache.get(piece_bytes)
                        if cached is None:
                            cached = self._bpe_tokenize_piece(piece_bytes)
                            if len(piece_bytes) <= 64:
                                new_persistent_entries[piece_bytes] = cached
                        if self._cache_room(len(ascii_cache)):
                            ascii_cache[piece_text] = cached
                    unique_len_map[piece_text] = len(cached)
                total = sum(unique_len_map[piece] * count for piece, count in piece_counts.items())
                if new_persistent_entries:
                    self._persist_piece_entries(new_persistent_entries)
                return total

        count = 0
        last_piece: str | None = None
        last_cached_len = 0
        for piece_text in pieces:
            if piece_text == last_piece:
                count += last_cached_len
                continue

            cached = ascii_cache.get(piece_text)
            if cached is None:
                piece_bytes = piece_text.encode("ascii")
                cached = bpe_cache.get(piece_bytes)
                if cached is None:
                    cached = self._bpe_tokenize_piece(piece_bytes)
                    if len(piece_bytes) <= 64:
                        new_persistent_entries[piece_bytes] = cached
                if self._cache_room(len(ascii_cache)):
                    ascii_cache[piece_text] = cached

            cached_len = len(cached)
            count += cached_len
            last_piece = piece_text
            last_cached_len = cached_len
        if new_persistent_entries:
            self._persist_piece_entries(new_persistent_entries)
        return count

    def _encode_with_allowed_special_gpu(
        self,
        text: str,
        allowed_special: set[str],
        *,
        device: str,
        chunk_bytes: int,
        overlap_bytes: int,
        strict_verify: bool,
    ) -> list[int]:
        if not allowed_special:
            return self._encode_ordinary_gpu_impl(
                text,
                device=device,
                chunk_bytes=chunk_bytes,
                overlap_bytes=overlap_bytes,
                strict_verify=strict_verify,
            )

        special_regex = _special_token_regex(frozenset(allowed_special))
        out: list[int] = []
        start = 0
        for match in special_regex.finditer(text):
            match_start, match_end = match.span()
            if match_start > start:
                out.extend(
                    self._encode_ordinary_gpu_impl(
                        text[start:match_start],
                        device=device,
                        chunk_bytes=chunk_bytes,
                        overlap_bytes=overlap_bytes,
                        strict_verify=strict_verify,
                    )
                )
            out.append(self._special_token_to_id(match.group()))
            start = match_end

        if start < len(text):
            out.extend(
                self._encode_ordinary_gpu_impl(
                    text[start:],
                    device=device,
                    chunk_bytes=chunk_bytes,
                    overlap_bytes=overlap_bytes,
                    strict_verify=strict_verify,
                )
            )

        return out

    def _encode_with_allowed_special(self, text: str, allowed_special: set[str]) -> list[int]:
        if not allowed_special:
            return self.encode_ordinary(text)

        special_regex = _special_token_regex(frozenset(allowed_special))
        out: list[int] = []
        start = 0
        for match in special_regex.finditer(text):
            match_start, match_end = match.span()
            if match_start > start:
                out.extend(self.encode_ordinary(text[start:match_start]))
            out.append(self._special_token_to_id(match.group()))
            start = match_end

        if start < len(text):
            out.extend(self.encode_ordinary(text[start:]))

        return out

    def _count_with_allowed_special(self, text: str, allowed_special: set[str]) -> int:
        if not allowed_special:
            return self._count_ordinary_impl(text)

        special_regex = _special_token_regex(frozenset(allowed_special))
        count = 0
        start = 0
        for match in special_regex.finditer(text):
            match_start, match_end = match.span()
            if match_start > start:
                count += self._count_ordinary_impl(text[start:match_start])
            count += 1
            start = match_end

        if start < len(text):
            count += self._count_ordinary_impl(text[start:])

        return count

    def _count_with_allowed_special_up_to_limit(
        self,
        text: str,
        allowed_special: set[str],
        token_limit: int,
    ) -> int | bool:
        if not allowed_special:
            return self._count_ordinary_up_to_limit_impl(text, token_limit)

        special_regex = _special_token_regex(frozenset(allowed_special))
        count = 0
        start = 0
        for match in special_regex.finditer(text):
            match_start, match_end = match.span()
            if match_start > start:
                segment = self._count_ordinary_up_to_limit_impl(text[start:match_start], token_limit - count)
                if segment is False:
                    return False
                count += int(segment)
                if count > token_limit:
                    return False

            count += 1
            if count > token_limit:
                return False
            start = match_end

        if start < len(text):
            segment = self._count_ordinary_up_to_limit_impl(text[start:], token_limit - count)
            if segment is False:
                return False
            count += int(segment)
            if count > token_limit:
                return False

        return count

    def _resolve_chat_template(
        self,
        template: str | Mapping[str, str] | None,
    ) -> tuple[dict[str, str | None], set[str]]:
        if template is None or template == _CHAT_TEMPLATE_TURBOTOKEN_V1:
            config: dict[str, str | None] = {
                "message_prefix": "[[role:{role}]]\n",
                "message_suffix": "\n[[/message]]\n",
                "assistant_prefix": "[[role:{role}]]\n",
            }
        elif template == _CHAT_TEMPLATE_IM_TOKENS:
            config = {
                "message_prefix": f"{_CHAT_START}" + "{role}\n",
                "message_suffix": f"{_CHAT_END}\n",
                "assistant_prefix": f"{_CHAT_START}" + "{role}\n",
            }
        elif isinstance(template, Mapping):
            message_prefix = template.get("message_prefix")
            if not isinstance(message_prefix, str) or not message_prefix:
                raise ValueError("chat template requires non-empty string 'message_prefix'")
            message_suffix = template.get("message_suffix", "")
            if not isinstance(message_suffix, str):
                raise ValueError("chat template field 'message_suffix' must be a string")
            assistant_prefix_raw = template.get("assistant_prefix")
            if assistant_prefix_raw is None:
                assistant_prefix: str | None = None
            elif isinstance(assistant_prefix_raw, str):
                assistant_prefix = assistant_prefix_raw
            else:
                raise ValueError("chat template field 'assistant_prefix' must be a string or null")
            config = {
                "message_prefix": message_prefix,
                "message_suffix": message_suffix,
                "assistant_prefix": assistant_prefix,
            }
        else:
            raise ValueError(
                "chat template must be 'turbotoken_v1', 'im_tokens', or a mapping template config"
            )

        special_tokens: set[str] = set()
        probe_parts = [
            config["message_prefix"].replace("{role}", "assistant"),
            config["message_suffix"],
        ]
        assistant_prefix = config["assistant_prefix"]
        if assistant_prefix:
            probe_parts.append(assistant_prefix.replace("{role}", "assistant"))
        for token in self._spec.special_tokens:
            if token and any(token in part for part in probe_parts):
                special_tokens.add(token)
        return config, special_tokens

    def _iter_chat_segments(
        self,
        messages: Iterable[Mapping[str, Any]],
        *,
        template_config: Mapping[str, str | None],
        prime_with_assistant_response: str | None,
    ):
        for message in messages:
            if not isinstance(message, Mapping):
                raise TypeError("chat messages must be mapping-like objects with role/name/content keys")
            role_value = message.get("name", message.get("role", "user"))
            if not isinstance(role_value, str) or not role_value:
                role_value = "user"

            content = message.get("content", "")
            if content is None:
                content = ""
            if not isinstance(content, str):
                content = str(content)

            yield template_config["message_prefix"].replace("{role}", role_value)
            if content:
                yield content
            yield template_config["message_suffix"]

        assistant_prefix = template_config["assistant_prefix"]
        if prime_with_assistant_response and assistant_prefix:
            yield assistant_prefix.replace("{role}", prime_with_assistant_response)

    def encode(
        self,
        text: str,
        *,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ) -> list[int]:
        allowed_set = self._allowed_special_set(allowed_special)
        disallowed_set = self._disallowed_special_set(disallowed_special) - allowed_set
        self._raise_if_disallowed_special(text, disallowed_set)
        try:
            return self._encode_with_allowed_special(text, allowed_set)
        except UnicodeEncodeError:
            return self._encode_with_allowed_special(_sanitize_text(text), allowed_set)

    def encode_generator(
        self,
        text: str,
        *,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ):
        allowed_set = self._allowed_special_set(allowed_special)
        disallowed_set = self._disallowed_special_set(disallowed_special) - allowed_set
        self._raise_if_disallowed_special(text, disallowed_set)

        try:
            source = text
            self.load_mergeable_ranks()
        except UnicodeEncodeError:
            source = _sanitize_text(text)
            self.load_mergeable_ranks()

        if not allowed_set:
            for piece_bytes in self._ordinary_piece_bytes(source):
                yield list(self._bpe_tokenize_piece(piece_bytes))
            return

        special_regex = _special_token_regex(frozenset(allowed_set))
        start = 0
        for match in special_regex.finditer(source):
            match_start, match_end = match.span()
            if match_start > start:
                yield self.encode_ordinary(source[start:match_start])
            yield [self._special_token_to_id(match.group())]
            start = match_end

        if start < len(source):
            yield self.encode_ordinary(source[start:])

    def encode_chat_generator(
        self,
        messages: Iterable[Mapping[str, Any]],
        *,
        prime_with_assistant_response: str | None = "assistant",
        template: str | Mapping[str, str] | None = _CHAT_TEMPLATE_TURBOTOKEN_V1,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ):
        template_config, template_special_tokens = self._resolve_chat_template(template)
        allowed_set = self._allowed_special_set(allowed_special)
        allowed_set.update(template_special_tokens)
        disallowed_set = self._disallowed_special_set(disallowed_special) - allowed_set

        for segment in self._iter_chat_segments(
            messages,
            template_config=template_config,
            prime_with_assistant_response=prime_with_assistant_response,
        ):
            self._raise_if_disallowed_special(segment, disallowed_set)
            try:
                yield self.encode(
                    segment,
                    allowed_special=allowed_set,
                    disallowed_special=disallowed_set,
                )
            except UnicodeEncodeError:
                yield self.encode(
                    _sanitize_text(segment),
                    allowed_special=allowed_set,
                    disallowed_special=disallowed_set,
                )

    def encode_chat(
        self,
        messages: Iterable[Mapping[str, Any]],
        *,
        prime_with_assistant_response: str | None = "assistant",
        template: str | Mapping[str, str] | None = _CHAT_TEMPLATE_TURBOTOKEN_V1,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ) -> list[int]:
        out: list[int] = []
        for chunk in self.encode_chat_generator(
            messages,
            prime_with_assistant_response=prime_with_assistant_response,
            template=template,
            allowed_special=allowed_special,
            disallowed_special=disallowed_special,
        ):
            out.extend(chunk)
        return out

    def encode_ordinary(self, text: str) -> list[int]:
        try:
            return self._encode_ordinary_impl(text)
        except UnicodeEncodeError:
            return self._encode_ordinary_impl(_sanitize_text(text))

    def encode_single_token(self, text_or_bytes: str | bytes) -> int:
        if isinstance(text_or_bytes, str):
            if text_or_bytes in self._spec.special_tokens:
                return self._special_token_to_id(text_or_bytes)
            token_bytes = text_or_bytes.encode("utf-8")
        else:
            token_bytes = text_or_bytes
            for special_text, special_token in self._spec.special_tokens.items():
                if token_bytes == special_text.encode("utf-8"):
                    return special_token

        token = self.load_mergeable_ranks().get(token_bytes)
        if token is None:
            raise KeyError(f"Token {text_or_bytes!r} is not a single vocabulary token")
        return token

    def _map_batch(self, items: list[T], fn: Callable[[T], U], *, num_threads: int) -> list[U]:
        if num_threads <= 1:
            return [fn(item) for item in items]

        from concurrent.futures import ThreadPoolExecutor

        with ThreadPoolExecutor(max_workers=num_threads) as pool:
            return list(pool.map(fn, items))

    def encode_ordinary_batch(self, text: list[str], *, num_threads: int = 8) -> list[list[int]]:
        return self._map_batch(text, self.encode_ordinary, num_threads=num_threads)

    def encode_batch(
        self,
        text: list[str],
        *,
        num_threads: int = 8,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ) -> list[list[int]]:
        def _encode_one(item: str) -> list[int]:
            return self.encode(
                item,
                allowed_special=allowed_special,
                disallowed_special=disallowed_special,
            )

        return self._map_batch(text, _encode_one, num_threads=num_threads)

    def encode_gpu(
        self,
        texts: list[str],
        *,
        device: str = "auto",
        chunk_bytes: int = 16_384,
        overlap_bytes: int = 512,
        strict_verify: bool = True,
        num_threads: int = 1,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ) -> list[list[int]]:
        if device not in {"auto", "metal"}:
            raise ValueError("encode_gpu currently supports device='auto' or device='metal'")
        if chunk_bytes <= 0:
            raise ValueError("chunk_bytes must be > 0")
        if overlap_bytes <= 0:
            raise ValueError("overlap_bytes must be > 0")

        allowed_set = self._allowed_special_set(allowed_special)
        disallowed_set = self._disallowed_special_set(disallowed_special) - allowed_set

        def _encode_one(item: str) -> list[int]:
            self._raise_if_disallowed_special(item, disallowed_set)
            try:
                return self._encode_with_allowed_special_gpu(
                    item,
                    allowed_set,
                    device=device,
                    chunk_bytes=chunk_bytes,
                    overlap_bytes=overlap_bytes,
                    strict_verify=strict_verify,
                )
            except UnicodeEncodeError:
                return self._encode_with_allowed_special_gpu(
                    _sanitize_text(item),
                    allowed_set,
                    device=device,
                    chunk_bytes=chunk_bytes,
                    overlap_bytes=overlap_bytes,
                    strict_verify=strict_verify,
                )

        return self._map_batch(texts, _encode_one, num_threads=num_threads)

    def count_gpu(
        self,
        texts: list[str],
        *,
        device: str = "auto",
        chunk_bytes: int = 16_384,
        overlap_bytes: int = 512,
        strict_verify: bool = True,
        num_threads: int = 1,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ) -> list[int]:
        encoded = self.encode_gpu(
            texts,
            device=device,
            chunk_bytes=chunk_bytes,
            overlap_bytes=overlap_bytes,
            strict_verify=strict_verify,
            num_threads=num_threads,
            allowed_special=allowed_special,
            disallowed_special=disallowed_special,
        )
        return [len(tokens) for tokens in encoded]

    def decode_bytes(self, tokens: list[int]) -> bytes:
        if tokens:
            native_decode_enable = os.environ.get("TURBOTOKEN_NATIVE_DECODE_ENABLE", "").strip().lower() in {
                "1",
                "true",
                "yes",
            }
            native_decode_disable = os.environ.get("TURBOTOKEN_NATIVE_DECODE_DISABLE", "").strip().lower() in {
                "1",
                "true",
                "yes",
            }
            if native_decode_enable and not native_decode_disable and len(tokens) >= self._native_decode_min_tokens():
                session = self._native_rank_session()
                if session is not None:
                    native = session.decode_bpe(tokens)
                    if native is not None:
                        return native

        self._ensure_decoder()
        assert self._decoder is not None

        try:
            return b"".join([self._decoder[token] for token in tokens])
        except KeyError as exc:
            raise ValueError(f"Unknown token id: {exc.args[0]}") from exc

    def decode_single_token_bytes(self, token: int) -> bytes:
        self._ensure_decoder()
        assert self._decoder is not None
        token_bytes = self._decoder.get(token)
        if token_bytes is None:
            raise KeyError(f"Unknown token id: {token}")
        return token_bytes

    def decode_tokens_bytes(self, tokens: list[int]) -> list[bytes]:
        return [self.decode_single_token_bytes(token) for token in tokens]

    def decode_with_offsets(self, tokens: list[int]) -> tuple[str, list[int]]:
        token_bytes = self.decode_tokens_bytes(tokens)

        text_len = 0
        offsets: list[int] = []
        for token in token_bytes:
            if not token:
                offsets.append(text_len)
                continue
            offsets.append(max(0, text_len - int(0x80 <= token[0] < 0xC0)))
            text_len += sum(1 for byte in token if not 0x80 <= byte < 0xC0)

        text = b"".join(token_bytes).decode("utf-8", errors="strict")
        return text, offsets

    def decode(self, tokens: list[int], errors: str = "replace") -> str:
        return self.decode_bytes(tokens).decode("utf-8", errors=errors)

    def decode_generator(self, tokens: list[int], *, errors: str = "replace"):
        import codecs

        incremental = codecs.getincrementaldecoder("utf-8")(errors=errors)
        for token_bytes in self.decode_tokens_bytes(tokens):
            chunk = incremental.decode(token_bytes, final=False)
            if chunk:
                yield chunk
        tail = incremental.decode(b"", final=True)
        if tail:
            yield tail

    def decode_batch(self, batch: list[list[int]], *, num_threads: int = 8) -> list[str]:
        return self._map_batch(batch, self.decode, num_threads=num_threads)

    def encode_to_numpy(
        self,
        text: str,
        *,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ):
        try:
            import numpy as np
        except ModuleNotFoundError as exc:
            raise RuntimeError("encode_to_numpy requires numpy to be installed") from exc

        encoded = self.encode(text, allowed_special=allowed_special, disallowed_special=disallowed_special)
        return np.asarray(encoded, dtype=np.uint32)

    def token_byte_values(self) -> list[bytes]:
        self._ensure_token_byte_values()
        assert self._token_byte_values_cache is not None
        return list(self._token_byte_values_cache)

    def count(
        self,
        text: str,
        *,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ) -> int:
        allowed_set = self._allowed_special_set(allowed_special)
        disallowed_set = self._disallowed_special_set(disallowed_special) - allowed_set
        self._raise_if_disallowed_special(text, disallowed_set)
        try:
            return self._count_with_allowed_special(text, allowed_set)
        except UnicodeEncodeError:
            return self._count_with_allowed_special(_sanitize_text(text), allowed_set)

    def count_tokens(
        self,
        text: str,
        *,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ) -> int:
        return self.count(
            text,
            allowed_special=allowed_special,
            disallowed_special=disallowed_special,
        )

    def count_chat(
        self,
        messages: Iterable[Mapping[str, Any]],
        *,
        prime_with_assistant_response: str | None = "assistant",
        template: str | Mapping[str, str] | None = _CHAT_TEMPLATE_TURBOTOKEN_V1,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ) -> int:
        template_config, template_special_tokens = self._resolve_chat_template(template)
        allowed_set = self._allowed_special_set(allowed_special)
        allowed_set.update(template_special_tokens)
        disallowed_set = self._disallowed_special_set(disallowed_special) - allowed_set

        total = 0
        for segment in self._iter_chat_segments(
            messages,
            template_config=template_config,
            prime_with_assistant_response=prime_with_assistant_response,
        ):
            self._raise_if_disallowed_special(segment, disallowed_set)
            try:
                total += self._count_with_allowed_special(segment, allowed_set)
            except UnicodeEncodeError:
                total += self._count_with_allowed_special(_sanitize_text(segment), allowed_set)
        return total

    def count_chat_tokens(
        self,
        messages: Iterable[Mapping[str, Any]],
        *,
        prime_with_assistant_response: str | None = "assistant",
        template: str | Mapping[str, str] | None = _CHAT_TEMPLATE_TURBOTOKEN_V1,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ) -> int:
        return self.count_chat(
            messages,
            prime_with_assistant_response=prime_with_assistant_response,
            template=template,
            allowed_special=allowed_special,
            disallowed_special=disallowed_special,
        )

    def is_within_token_limit(
        self,
        text: str,
        token_limit: int,
        *,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ) -> int | bool:
        if token_limit < 0:
            raise ValueError("token_limit must be >= 0")

        allowed_set = self._allowed_special_set(allowed_special)
        disallowed_set = self._disallowed_special_set(disallowed_special) - allowed_set
        self._raise_if_disallowed_special(text, disallowed_set)
        try:
            return self._count_with_allowed_special_up_to_limit(text, allowed_set, token_limit)
        except UnicodeEncodeError:
            return self._count_with_allowed_special_up_to_limit(
                _sanitize_text(text),
                allowed_set,
                token_limit,
            )

    def encode_file_native(
        self,
        path: str | bytes | os.PathLike[str] | os.PathLike[bytes],
    ) -> list[int] | None:
        """Encode file bytes via native rank-BPE C ABI (raw byte-path, no regex framing)."""
        session = self._native_rank_session()
        if session is None:
            return None
        return session.encode_bpe_file(path)

    def count_file_native(
        self,
        path: str | bytes | os.PathLike[str] | os.PathLike[bytes],
    ) -> int | None:
        """Count file bytes via native rank-BPE C ABI (raw byte-path, no regex framing)."""
        session = self._native_rank_session()
        if session is None:
            return None
        return session.count_bpe_file(path)

    def is_file_within_token_limit_native(
        self,
        path: str | bytes | os.PathLike[str] | os.PathLike[bytes],
        token_limit: int,
    ) -> int | bool | None:
        """Token-limit check for file bytes via native rank-BPE C ABI (raw byte-path)."""
        if token_limit < 0:
            raise ValueError("token_limit must be >= 0")
        session = self._native_rank_session()
        if session is None:
            return None
        return session.is_within_token_limit_bpe_file(path, token_limit)

    def is_chat_within_token_limit(
        self,
        messages: Iterable[Mapping[str, Any]],
        token_limit: int,
        *,
        prime_with_assistant_response: str | None = "assistant",
        template: str | Mapping[str, str] | None = _CHAT_TEMPLATE_TURBOTOKEN_V1,
        allowed_special: AllowedSpecial = set(),  # noqa: B006
        disallowed_special: DisallowedSpecial = "all",
    ) -> int | bool:
        if token_limit < 0:
            raise ValueError("token_limit must be >= 0")

        template_config, template_special_tokens = self._resolve_chat_template(template)
        allowed_set = self._allowed_special_set(allowed_special)
        allowed_set.update(template_special_tokens)
        disallowed_set = self._disallowed_special_set(disallowed_special) - allowed_set

        total = 0
        for segment in self._iter_chat_segments(
            messages,
            template_config=template_config,
            prime_with_assistant_response=prime_with_assistant_response,
        ):
            self._raise_if_disallowed_special(segment, disallowed_set)
            try:
                piece = self._count_with_allowed_special_up_to_limit(segment, allowed_set, token_limit - total)
            except UnicodeEncodeError:
                piece = self._count_with_allowed_special_up_to_limit(
                    _sanitize_text(segment),
                    allowed_set,
                    token_limit - total,
                )
            if piece is False:
                return False
            total += int(piece)
            if total > token_limit:
                return False
        return total

    def count_batch(self, texts: list[str], *, num_threads: int = 8) -> list[int]:
        return self._map_batch(texts, self.count, num_threads=num_threads)

    def _ensure_decoder(self) -> None:
        if self._decoder is not None:
            return

        if self._mergeable_ranks_cache is not None:
            self._decoder = {token_id: token_bytes for token_bytes, token_id in self._mergeable_ranks_cache.items()}
        else:
            self._decoder = load_decoder_only(self.name)
        for token_text, token_id in self._spec.special_tokens.items():
            self._decoder[token_id] = token_text.encode("utf-8")

    def _ensure_token_byte_values(self) -> None:
        if self._token_byte_values_cache is not None:
            return

        mergeable_ranks = self.load_mergeable_ranks()
        self._token_byte_values_cache = sorted(mergeable_ranks.keys())

    def _ensure_vocab_tables(self) -> None:
        # Compatibility helper for callers/tests that expect both caches.
        self._ensure_decoder()
        self._ensure_token_byte_values()

    def rank_file_path(self, *, cache_dir: "Path | None" = None) -> "Path":
        return rank_file_path(self.name, dir_path=cache_dir)

    def ensure_rank_file(self, *, cache_dir: "Path | None" = None, force: bool = False) -> "Path":
        return ensure_rank_file(self.name, dir_path=cache_dir, force=force)

    def load_mergeable_ranks(self, *, cache_dir: "Path | None" = None, force: bool = False) -> dict[bytes, int]:
        if self._mergeable_ranks_cache is not None and not force:
            return self._mergeable_ranks_cache

        ranks = load_ranks_only(self.name, dir_path=cache_dir, force=force)
        self._rank_payload_cache = None
        self._native_rank_session_cache = None
        self._native_rank_payload_ref = None
        self._mergeable_ranks_cache = ranks
        self._decoder = None
        self._token_byte_values_cache = None
        self._bpe_cache.clear()
        self._ascii_text_bpe_cache.clear()
        return self._mergeable_ranks_cache



def get_encoding(name: str) -> Encoding:
    spec = get_encoding_spec(name)
    return Encoding(name=spec.name, _spec=spec)



def encoding_for_model(model: str) -> Encoding:
    return get_encoding(model_to_encoding(model))



def list_encoding_names() -> list[str]:
    return _list_encoding_names()
