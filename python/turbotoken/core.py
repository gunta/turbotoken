from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any, AbstractSet, Callable, Collection, Literal, TypeVar

from ._rank_files import ensure_rank_file, parse_rank_file_bytes, rank_file_path
from ._registry import EncodingSpec, get_encoding_spec
from ._registry import list_encoding_names as _list_encoding_names
from ._registry import model_to_encoding

AllowedSpecial = Literal["all"] | AbstractSet[str]
DisallowedSpecial = Literal["all"] | Collection[str]
T = TypeVar("T")
U = TypeVar("U")


def _sanitize_text(text: str) -> str:
    # Match tiktoken's surrogate handling so encode/decode stay resilient on odd input.
    return text.encode("utf-16", "surrogatepass").decode("utf-16", "replace")


@lru_cache(maxsize=128)
def _special_token_regex(tokens: frozenset[str]):
    import regex

    if not tokens:
        return regex.compile(r"(?!x)x")

    pattern = "|".join(regex.escape(token) for token in sorted(tokens, key=len, reverse=True))
    return regex.compile(pattern)


@dataclass(slots=True)
class Encoding:
    name: str
    _spec: EncodingSpec
    _mergeable_ranks_cache: dict[bytes, int] | None = field(default=None, init=False, repr=False)
    _decoder: dict[int, bytes] | None = field(default=None, init=False, repr=False)
    _token_byte_values_cache: list[bytes] | None = field(default=None, init=False, repr=False)
    _piece_regex: Any | None = field(default=None, init=False, repr=False)
    _bpe_cache: dict[bytes, tuple[int, ...]] = field(default_factory=dict, init=False, repr=False)

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
            if len(self._bpe_cache) < 100_000:
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
        if len(self._bpe_cache) < 100_000:
            self._bpe_cache[piece] = result
        return result

    def _encode_bytes(self, data: bytes) -> list[int]:
        if not data:
            return []
        return list(self._bpe_tokenize_piece(data))

    def _encode_ordinary_impl(self, text: str) -> list[int]:
        if not text:
            return []
        piece_regex = self._ensure_piece_regex()
        out: list[int] = []
        for piece in piece_regex.findall(text):
            if not piece:
                continue
            out.extend(self._bpe_tokenize_piece(piece.encode("utf-8")))
        return out

    def _count_ordinary_impl(self, text: str) -> int:
        if not text:
            return 0
        piece_regex = self._ensure_piece_regex()
        count = 0
        for piece in piece_regex.findall(text):
            if not piece:
                continue
            count += len(self._bpe_tokenize_piece(piece.encode("utf-8")))
        return count

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

        token = self.load_mergeable_ranks().get(token_bytes)
        if token is None:
            raise KeyError(f"Token {text_or_bytes!r} is not a single vocabulary token")
        return token

    def _map_batch(self, items: list[T], fn: Callable[[T], U], *, num_threads: int) -> list[U]:
        if num_threads <= 1:
            return [fn(item) for item in items]

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

    def decode_bytes(self, tokens: list[int]) -> bytes:
        self._ensure_vocab_tables()
        assert self._decoder is not None

        pieces: list[bytes] = []
        for token in tokens:
            token_bytes = self._decoder.get(token)
            if token_bytes is None:
                raise ValueError(f"Unknown token id: {token}")
            pieces.append(token_bytes)
        return b"".join(pieces)

    def decode_single_token_bytes(self, token: int) -> bytes:
        self._ensure_vocab_tables()
        assert self._decoder is not None
        token_bytes = self._decoder.get(token)
        if token_bytes is None:
            raise ValueError(f"Unknown token id: {token}")
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
        self._ensure_vocab_tables()
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

    def count_batch(self, texts: list[str], *, num_threads: int = 8) -> list[int]:
        return self._map_batch(texts, self.count, num_threads=num_threads)

    def _ensure_vocab_tables(self) -> None:
        if self._decoder is not None and self._token_byte_values_cache is not None:
            return

        mergeable_ranks = self.load_mergeable_ranks()
        self._decoder = {token_id: token_bytes for token_bytes, token_id in mergeable_ranks.items()}
        for token_text, token_id in self._spec.special_tokens.items():
            self._decoder[token_id] = token_text.encode("utf-8")
        self._token_byte_values_cache = sorted(mergeable_ranks.keys())

    def rank_file_path(self, *, cache_dir: Path | None = None) -> Path:
        return rank_file_path(self.name, dir_path=cache_dir)

    def ensure_rank_file(self, *, cache_dir: Path | None = None, force: bool = False) -> Path:
        return ensure_rank_file(self.name, dir_path=cache_dir, force=force)

    def load_mergeable_ranks(self, *, cache_dir: Path | None = None, force: bool = False) -> dict[bytes, int]:
        if self._mergeable_ranks_cache is not None and not force:
            return self._mergeable_ranks_cache

        rank_path = self.ensure_rank_file(cache_dir=cache_dir, force=force)
        self._mergeable_ranks_cache = parse_rank_file_bytes(rank_path.read_bytes())
        self._decoder = None
        self._token_byte_values_cache = None
        self._bpe_cache.clear()
        return self._mergeable_ranks_cache



def get_encoding(name: str) -> Encoding:
    spec = get_encoding_spec(name)
    return Encoding(name=spec.name, _spec=spec)



def encoding_for_model(model: str) -> Encoding:
    return get_encoding(model_to_encoding(model))



def list_encoding_names() -> list[str]:
    return _list_encoding_names()
