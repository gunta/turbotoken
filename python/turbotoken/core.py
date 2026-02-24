from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Literal, TypeVar

from ._native import get_native_bridge
from ._rank_files import ensure_rank_file, parse_rank_file_bytes, rank_file_path
from ._registry import EncodingSpec, get_encoding_spec
from ._registry import list_encoding_names as _list_encoding_names
from ._registry import model_to_encoding

SpecialTokenPolicy = Literal["all"] | set[str]
T = TypeVar("T")
U = TypeVar("U")


@dataclass(slots=True)
class Encoding:
    name: str
    _spec: EncodingSpec
    _mergeable_ranks: dict[bytes, int] | None = field(default=None, init=False, repr=False)

    @property
    def n_vocab(self) -> int:
        return self._spec.n_vocab

    @property
    def eot_token(self) -> int:
        return self._spec.eot_token

    @property
    def special_tokens_set(self) -> set[str]:
        return set(self._spec.special_tokens)

    def _allowed_special_set(self, allowed_special: SpecialTokenPolicy) -> set[str]:
        if allowed_special == "all":
            return set(self._spec.special_tokens)
        return set(allowed_special)

    def _disallowed_special_set(self, disallowed_special: SpecialTokenPolicy) -> set[str]:
        if disallowed_special == "all":
            return set(self._spec.special_tokens)
        return set(disallowed_special)

    def _special_token_to_id(self, token: str) -> int:
        if token == "<|endoftext|>":
            return self.eot_token
        raise KeyError(f"Unknown special token: {token!r}")

    def _raise_if_disallowed_special(self, text: str, disallowed_special: set[str]) -> None:
        for token in disallowed_special:
            if token in text:
                raise ValueError(
                    "Encountered disallowed special token in input text. "
                    f"Token={token!r}. Pass allowed_special to permit it."
                )

    def _encode_with_allowed_special(self, text: str, allowed_special: set[str]) -> list[int]:
        if not allowed_special:
            return self.encode_ordinary(text)

        tokens_by_length = sorted(allowed_special, key=len, reverse=True)
        out: list[int] = []
        i = 0
        while i < len(text):
            matched = None
            for token in tokens_by_length:
                if text.startswith(token, i):
                    matched = token
                    break

            if matched is not None:
                out.append(self._special_token_to_id(matched))
                i += len(matched)
                continue

            out.extend(text[i].encode("utf-8"))
            i += 1

        return out

    def _count_with_allowed_special(self, text: str, allowed_special: set[str]) -> int:
        if not allowed_special:
            return len(text.encode("utf-8"))

        tokens_by_length = sorted(allowed_special, key=len, reverse=True)
        count = 0
        i = 0
        while i < len(text):
            matched = None
            for token in tokens_by_length:
                if text.startswith(token, i):
                    matched = token
                    break

            if matched is not None:
                count += 1
                i += len(matched)
                continue

            count += len(text[i].encode("utf-8"))
            i += 1

        return count

    def encode(
        self,
        text: str,
        *,
        allowed_special: SpecialTokenPolicy | None = None,
        disallowed_special: SpecialTokenPolicy = "all",
    ) -> list[int]:
        allowed_set = set() if allowed_special is None else self._allowed_special_set(allowed_special)
        disallowed_set = self._disallowed_special_set(disallowed_special) - allowed_set
        self._raise_if_disallowed_special(text, disallowed_set)
        # Placeholder path: non-special pieces are UTF-8 byte values, not BPE merges.
        return self._encode_with_allowed_special(text, allowed_set)

    def encode_ordinary(self, text: str) -> list[int]:
        return list(text.encode("utf-8"))

    def encode_single_token(self, text_or_bytes: str | bytes) -> int:
        if isinstance(text_or_bytes, bytes):
            if len(text_or_bytes) != 1:
                raise KeyError("Placeholder tokenizer can only encode single-byte byte tokens")
            return text_or_bytes[0]

        if text_or_bytes in self._spec.special_tokens:
            return self._special_token_to_id(text_or_bytes)

        encoded = text_or_bytes.encode("utf-8")
        if len(encoded) != 1:
            raise KeyError("Placeholder tokenizer can only encode single-byte text tokens")
        return encoded[0]

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
        allowed_special: SpecialTokenPolicy | None = None,
        disallowed_special: SpecialTokenPolicy = "all",
    ) -> list[list[int]]:
        def _encode_one(item: str) -> list[int]:
            return self.encode(
                item,
                allowed_special=allowed_special,
                disallowed_special=disallowed_special,
            )

        return self._map_batch(text, _encode_one, num_threads=num_threads)

    def decode_bytes(self, tokens: list[int]) -> bytes:
        out = bytearray()
        for token in tokens:
            if 0 <= token <= 255:
                out.append(token)
                continue

            if token == self.eot_token:
                out.extend(b"<|endoftext|>")
                continue

            raise ValueError(f"Token out of placeholder decode range: {token}")

        return bytes(out)

    def decode_single_token_bytes(self, token: int) -> bytes:
        return self.decode_bytes([token])

    def decode(self, tokens: list[int], errors: str = "replace") -> str:
        return self.decode_bytes(tokens).decode("utf-8", errors=errors)

    def decode_batch(self, batch: list[list[int]], *, num_threads: int = 8) -> list[str]:
        return self._map_batch(batch, self.decode, num_threads=num_threads)

    def encode_to_numpy(
        self,
        text: str,
        *,
        allowed_special: SpecialTokenPolicy | None = None,
        disallowed_special: SpecialTokenPolicy = "all",
    ):
        try:
            import numpy as np
        except ModuleNotFoundError as exc:
            raise RuntimeError("encode_to_numpy requires numpy to be installed") from exc

        encoded = self.encode(text, allowed_special=allowed_special, disallowed_special=disallowed_special)
        return np.asarray(encoded, dtype=np.uint32)

    def token_byte_values(self) -> list[bytes]:
        return [bytes([i]) for i in range(256)]

    def count(
        self,
        text: str,
        *,
        allowed_special: SpecialTokenPolicy | None = None,
        disallowed_special: SpecialTokenPolicy = "all",
    ) -> int:
        allowed_set = set() if allowed_special is None else self._allowed_special_set(allowed_special)
        disallowed_set = self._disallowed_special_set(disallowed_special) - allowed_set
        self._raise_if_disallowed_special(text, disallowed_set)

        # Fast scaffold path: call native C ABI when input has no special token markers.
        if not any(token in text for token in self._spec.special_tokens):
            data = text.encode("utf-8")
            native_count = get_native_bridge().count_bytes(data)
            if native_count is not None:
                return native_count

        return self._count_with_allowed_special(text, allowed_set)

    def count_batch(self, texts: list[str], *, num_threads: int = 8) -> list[int]:
        return self._map_batch(texts, self.count, num_threads=num_threads)

    def rank_file_path(self, *, cache_dir: Path | None = None) -> Path:
        return rank_file_path(self.name, dir_path=cache_dir)

    def ensure_rank_file(self, *, cache_dir: Path | None = None, force: bool = False) -> Path:
        return ensure_rank_file(self.name, dir_path=cache_dir, force=force)

    def load_mergeable_ranks(self, *, cache_dir: Path | None = None, force: bool = False) -> dict[bytes, int]:
        if self._mergeable_ranks is not None and not force:
            return self._mergeable_ranks

        rank_path = self.ensure_rank_file(cache_dir=cache_dir, force=force)
        self._mergeable_ranks = parse_rank_file_bytes(rank_path.read_bytes())
        return self._mergeable_ranks



def get_encoding(name: str) -> Encoding:
    spec = get_encoding_spec(name)
    return Encoding(name=spec.name, _spec=spec)



def encoding_for_model(model: str) -> Encoding:
    return get_encoding(model_to_encoding(model))



def list_encoding_names() -> list[str]:
    return _list_encoding_names()
