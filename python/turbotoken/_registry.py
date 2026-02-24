from __future__ import annotations

from dataclasses import dataclass

_MODEL_TO_ENCODING = {
    "gpt-4o": "o200k_base",
    "gpt-4.1": "o200k_base",
    "gpt-4": "cl100k_base",
    "gpt-3.5-turbo": "cl100k_base",
}


@dataclass(frozen=True, slots=True)
class EncodingSpec:
    name: str
    rank_file_url: str
    # Placeholder metadata until true vocab/special-token tables are wired from rank files.
    n_vocab: int = 257
    eot_token: int = 256
    special_tokens: frozenset[str] = frozenset({"<|endoftext|>"})


_ENCODING_SPECS = {
    "o200k_base": EncodingSpec(
        name="o200k_base",
        rank_file_url="https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
    ),
    "cl100k_base": EncodingSpec(
        name="cl100k_base",
        rank_file_url="https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
    ),
    "p50k_base": EncodingSpec(
        name="p50k_base",
        rank_file_url="https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
    ),
    "r50k_base": EncodingSpec(
        name="r50k_base",
        rank_file_url="https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
    ),
}


def list_encoding_names() -> list[str]:
    return sorted(_ENCODING_SPECS.keys())


def get_encoding_spec(name: str) -> EncodingSpec:
    try:
        return _ENCODING_SPECS[name]
    except KeyError as exc:
        supported = ", ".join(list_encoding_names())
        raise ValueError(f"Unknown encoding {name!r}. Supported encodings: {supported}") from exc


def model_to_encoding(model: str) -> str:
    # Keep scaffold behavior permissive until we mirror tiktoken's exact model table.
    return _MODEL_TO_ENCODING.get(model, "o200k_base")
