from __future__ import annotations

import heapq
import os
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from functools import lru_cache
from typing import TYPE_CHECKING, Any, Iterable

if TYPE_CHECKING:
    from .core import Encoding


_DEFAULT_TRAIN_PATTERN = "|".join(
    [
        r"""[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?""",
        r"""[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?""",
        r"""\p{N}{1,3}""",
        r""" ?[^\s\p{L}\p{N}]+[\r\n/]*""",
        r"""\s*[\r\n]+""",
        r"""\s+(?!\S)""",
        r"""\s+""",
    ]
)

_GPT4_TRAIN_PATTERN = (
    r"""'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]++[\r\n]*|\s*[\r\n]|\s+(?!\S)|\s+"""
)

_DEFAULT_TRAIN_PATTERN_ASCII = "|".join(
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

_GPT4_TRAIN_PATTERN_ASCII = (
    r"""'(?i:[sdmt]|ll|ve|re)|[^\r\nA-Za-z0-9]?[A-Za-z]+|\d{1,3}| ?[^\sA-Za-z0-9]+[\r\n]*|\s*[\r\n]|\s+(?!\S)|\s+"""
)


@lru_cache(maxsize=4)
def _compile_ascii_pattern(pattern: str) -> re.Pattern[str]:
    return re.compile(pattern)


@lru_cache(maxsize=1)
def _regex_module() -> Any:
    try:
        import regex as regex_mod
    except ModuleNotFoundError as exc:  # pragma: no cover - exercised in runtime environments
        raise ValueError("The 'regex' package is required for non-ASCII training patterns") from exc
    return regex_mod


@dataclass(slots=True)
class _CompiledPattern:
    pattern: str
    ascii_fast: re.Pattern[str] | None
    regex_compiled: Any | None = None

    def findall(self, text: str) -> list[str]:
        if self.ascii_fast is not None and text.isascii():
            return self.ascii_fast.findall(text)

        if self.regex_compiled is None:
            regex_mod = _regex_module()
            self.regex_compiled = regex_mod.compile(self.pattern)
        return self.regex_compiled.findall(text)


Pair = tuple[int, int]


@dataclass(slots=True)
class _Word:
    ids: list[int]

    def merge_pair(self, pair: Pair, new_id: int) -> list[tuple[Pair, int]]:
        a, b = pair
        ids = self.ids
        n = len(ids)
        if n < 2:
            return []

        first_match = -1
        for idx in range(n - 1):
            if ids[idx] == a and ids[idx + 1] == b:
                first_match = idx
                break
        if first_match < 0:
            return []

        out: list[int] = ids[:first_match]
        deltas: dict[Pair, int] = {}

        def bump_delta(changed_pair: Pair, delta: int) -> None:
            deltas[changed_pair] = deltas.get(changed_pair, 0) + delta

        i = first_match
        while i < n:
            if i + 1 < n and ids[i] == a and ids[i + 1] == b:
                left = out[-1] if out else None
                right = ids[i + 2] if i + 2 < n else None

                if left is not None:
                    bump_delta((left, a), -1)
                    bump_delta((left, new_id), 1)
                bump_delta((a, b), -1)
                if right is not None:
                    bump_delta((b, right), -1)
                    bump_delta((new_id, right), 1)

                out.append(new_id)
                i += 2
            else:
                out.append(ids[i])
                i += 1

        self.ids = out
        return [(changed_pair, delta) for changed_pair, delta in deltas.items() if delta != 0]


def _compile_pattern(pattern: str | None) -> tuple[str, _CompiledPattern]:
    pat = pattern if pattern is not None else _DEFAULT_TRAIN_PATTERN
    if pat == _DEFAULT_TRAIN_PATTERN:
        return pat, _CompiledPattern(
            pattern=pat,
            ascii_fast=_compile_ascii_pattern(_DEFAULT_TRAIN_PATTERN_ASCII),
        )
    if pat == _GPT4_TRAIN_PATTERN:
        return pat, _CompiledPattern(
            pattern=pat,
            ascii_fast=_compile_ascii_pattern(_GPT4_TRAIN_PATTERN_ASCII),
        )

    regex_mod = _regex_module()
    try:
        return pat, _CompiledPattern(
            pattern=pat,
            ascii_fast=None,
            regex_compiled=regex_mod.compile(pat),
        )
    except regex_mod.error as exc:
        raise ValueError(f"Invalid training regex pattern: {exc}") from exc


def _accumulate_chunks(
    texts: Iterable[str],
    compiled_pattern: _CompiledPattern,
    *,
    use_native_ascii_o200k: bool = False,
) -> Counter[bytes]:
    counts: Counter[bytes] = Counter()

    bridge = None
    if use_native_ascii_o200k and compiled_pattern.pattern == _DEFAULT_TRAIN_PATTERN:
        from ._native import get_native_bridge

        candidate = get_native_bridge()
        if candidate.available:
            bridge = candidate

    for text in texts:
        if not text:
            continue

        if bridge is not None:
            data = text.encode("utf-8")
            ranges = bridge.pretokenize_ascii_o200k_ranges(data)
            if ranges is not None:
                for start, end in ranges:
                    counts[data[start:end]] += 1
                continue

        local: Counter[str] = Counter(compiled_pattern.findall(text))
        local.pop("", None)
        for piece, count in local.items():
            counts[piece.encode("utf-8")] += count

    return counts


def _initial_pair_state(
    words: list[_Word],
    counts: list[int],
) -> tuple[dict[Pair, int], dict[Pair, set[int]]]:
    pair_counts: dict[Pair, int] = defaultdict(int)
    where_to_update: dict[Pair, set[int]] = defaultdict(set)

    for word_idx, word in enumerate(words):
        word_count = counts[word_idx]
        if word_count <= 0 or len(word.ids) < 2:
            continue

        prev = word.ids[0]
        for current in word.ids[1:]:
            pair = (prev, current)
            pair_counts[pair] += word_count
            where_to_update[pair].add(word_idx)
            prev = current

    return pair_counts, where_to_update


def _build_mergeable_ranks(merges: dict[Pair, int]) -> dict[bytes, int]:
    mergeable: dict[bytes, int] = {bytes([token]): token for token in range(256)}
    token_bytes: list[bytes] = [bytes([token]) for token in range(256)]

    for (left, right), merged_id in sorted(merges.items(), key=lambda item: item[1]):
        merged = token_bytes[left] + token_bytes[right]
        if len(token_bytes) <= merged_id:
            token_bytes.extend([b""] * (merged_id + 1 - len(token_bytes)))
        token_bytes[merged_id] = merged
        mergeable[merged] = merged_id

    return mergeable


def _flatten_chunk_counts(chunk_counts: Counter[bytes]) -> tuple[bytes, list[int], list[int]]:
    merged = bytearray()
    offsets: list[int] = [0]
    counts: list[int] = []
    for chunk, count in chunk_counts.items():
        merged.extend(chunk)
        offsets.append(len(merged))
        counts.append(int(count))
    return bytes(merged), offsets, counts


def _try_native_direct_ascii_o200k_train(
    texts: Iterable[str],
    *,
    vocab_size: int,
    min_frequency: int,
) -> dict[Pair, int] | None:
    if not isinstance(texts, (list, tuple)):
        return None

    encoded = bytearray()
    offsets: list[int] = [0]
    for text in texts:
        if not isinstance(text, str):
            return None
        encoded.extend(text.encode("utf-8"))
        offsets.append(len(encoded))

    if len(encoded) == 0:
        return {}

    from ._native import get_native_bridge

    bridge = get_native_bridge()
    if not bridge.available:
        return None

    merges = bridge.train_bpe_ascii_o200k_multi(
        bytes(encoded),
        offsets,
        vocab_size=vocab_size,
        min_frequency=min_frequency,
    )
    if merges is None:
        return None
    return {(int(left), int(right)): int(new_id) for left, right, new_id in merges}


def train_mergeable_ranks_from_iterator(
    texts: Iterable[str],
    *,
    vocab_size: int,
    pattern: str | None = None,
    min_frequency: int = 2,
) -> tuple[str, dict[bytes, int]]:
    if vocab_size < 256:
        raise ValueError(f"vocab_size must be >= 256, got {vocab_size}")
    if min_frequency < 1:
        raise ValueError(f"min_frequency must be >= 1, got {min_frequency}")

    route = os.environ.get("TURBOTOKEN_TRAINING_BACKEND", "auto").strip().lower()
    disable_native = os.environ.get("TURBOTOKEN_NATIVE_TRAINING_DISABLE", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }
    use_native = route == "native" and not disable_native
    if route not in {"auto", "native", "python"}:
        use_native = False
    enable_native_pretokenize = os.environ.get("TURBOTOKEN_TRAIN_NATIVE_PRETOKENIZE", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }
    enable_native_direct_ascii = os.environ.get("TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }
    force_native_training = os.environ.get("TURBOTOKEN_NATIVE_TRAINING_FORCE", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }

    pat_str, compiled = _compile_pattern(pattern)
    if use_native and enable_native_direct_ascii and pat_str == _DEFAULT_TRAIN_PATTERN:
        direct_merges = _try_native_direct_ascii_o200k_train(
            texts,
            vocab_size=vocab_size,
            min_frequency=min_frequency,
        )
        if direct_merges is not None:
            return pat_str, _build_mergeable_ranks(direct_merges)

    chunk_counts = _accumulate_chunks(
        texts,
        compiled,
        use_native_ascii_o200k=use_native and enable_native_pretokenize,
    )
    if not chunk_counts:
        return pat_str, {bytes([token]): token for token in range(256)}

    # Native merge training has higher setup/cffi overhead on small corpora.
    # Keep backend='native' semantics, but auto-route to the faster Python
    # trainer unless explicitly forced.
    if use_native and not force_native_training:
        estimated_training_bytes = sum(len(chunk) * int(count) for chunk, count in chunk_counts.items())
        if estimated_training_bytes < 2_000_000:
            use_native = False

    if use_native:
        from ._native import get_native_bridge

        bridge = get_native_bridge()
        if bridge.available:
            merged, offsets, counts = _flatten_chunk_counts(chunk_counts)
            native_merges = bridge.train_bpe_from_chunk_counts(
                merged,
                offsets,
                counts,
                vocab_size=vocab_size,
                min_frequency=min_frequency,
            )
            if native_merges is not None:
                merge_map = {
                    (int(left), int(right)): int(new_id)
                    for left, right, new_id in native_merges
                }
                return pat_str, _build_mergeable_ranks(merge_map)

    words = [_Word(list(chunk)) for chunk in chunk_counts.keys()]
    counts = [int(value) for value in chunk_counts.values()]
    pair_counts, where_to_update = _initial_pair_state(words, counts)

    heap: list[tuple[int, int, int, Pair, set[int]]] = []
    for pair, positions in where_to_update.items():
        count = pair_counts.get(pair, 0)
        if count > 0:
            heapq.heappush(heap, (-count, pair[0], pair[1], pair, positions))

    merges: dict[Pair, int] = {}
    merges_to_learn = vocab_size - 256
    merges_done = 0
    while merges_done < merges_to_learn and heap:
        neg_count, _, _, pair, positions = heapq.heappop(heap)

        current = pair_counts.get(pair, 0)
        if current != -neg_count:
            heapq.heappush(heap, (-current, pair[0], pair[1], pair, positions))
            continue
        if current < min_frequency:
            break

        new_id = 256 + merges_done
        merges[pair] = new_id

        local_updates: dict[Pair, set[int]] = defaultdict(set)
        for word_idx in positions:
            deltas = words[word_idx].merge_pair(pair, new_id)
            if not deltas:
                continue
            weight = counts[word_idx]
            if weight == 0:
                continue

            for changed_pair, delta in deltas:
                delta_total = delta * weight
                if delta_total == 0:
                    continue
                next_count = pair_counts.get(changed_pair, 0) + delta_total
                if next_count > 0:
                    pair_counts[changed_pair] = next_count
                else:
                    pair_counts.pop(changed_pair, None)
                if delta > 0:
                    local_updates[changed_pair].add(word_idx)

        for changed_pair, word_indices in local_updates.items():
            count = pair_counts.get(changed_pair, 0)
            if count <= 0:
                continue
            position_set = where_to_update.setdefault(changed_pair, set())
            position_set.update(word_indices)
            heapq.heappush(
                heap,
                (-count, changed_pair[0], changed_pair[1], changed_pair, position_set),
            )

        merges_done += 1

    return pat_str, _build_mergeable_ranks(merges)


def train_encoding_from_iterator(
    texts: Iterable[str],
    *,
    vocab_size: int,
    name: str = "turbotoken_trained",
    pattern: str | None = None,
    special_tokens: dict[str, int] | None = None,
    min_frequency: int = 2,
) -> "Encoding":
    from .core import Encoding

    pat_str, mergeable_ranks = train_mergeable_ranks_from_iterator(
        texts,
        vocab_size=vocab_size,
        pattern=pattern,
        min_frequency=min_frequency,
    )
    return Encoding(
        name,
        pat_str=pat_str,
        mergeable_ranks=mergeable_ranks,
        special_tokens={} if special_tokens is None else dict(special_tokens),
    )
