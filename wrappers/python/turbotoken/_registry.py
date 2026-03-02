from __future__ import annotations

ENDOFTEXT = "<|endoftext|>"
FIM_PREFIX = "<|fim_prefix|>"
FIM_MIDDLE = "<|fim_middle|>"
FIM_SUFFIX = "<|fim_suffix|>"
ENDOFPROMPT = "<|endofprompt|>"

_R50K_PAT_STR = (
    r"""'(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s"""
)
_CL100K_PAT_STR = (
    r"""'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s"""
)
_O200K_PAT_STR = "|".join(
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

_MODEL_PREFIX_TO_ENCODING: dict[str, str] = {
    "o1-": "o200k_base",
    "o3-": "o200k_base",
    "o4-mini-": "o200k_base",
    "gpt-5-": "o200k_base",
    "gpt-4.5-": "o200k_base",
    "gpt-4.1-": "o200k_base",
    "chatgpt-4o-": "o200k_base",
    "gpt-4o-": "o200k_base",
    "gpt-oss-": "o200k_harmony",
    "gpt-4-": "cl100k_base",
    "gpt-3.5-turbo-": "cl100k_base",
    "gpt-35-turbo-": "cl100k_base",
    "ft:gpt-4o": "o200k_base",
    "ft:gpt-4": "cl100k_base",
    "ft:gpt-3.5-turbo": "cl100k_base",
    "ft:davinci-002": "cl100k_base",
    "ft:babbage-002": "cl100k_base",
}

_MODEL_TO_ENCODING = {
    "o1": "o200k_base",
    "o3": "o200k_base",
    "o4-mini": "o200k_base",
    "gpt-5": "o200k_base",
    "gpt-4.1": "o200k_base",
    "gpt-4o": "o200k_base",
    "gpt-4o-mini": "o200k_base",
    "gpt-4.1-mini": "o200k_base",
    "gpt-4.1-nano": "o200k_base",
    "gpt-oss-120b": "o200k_harmony",
    "gpt-4": "cl100k_base",
    "gpt-3.5-turbo": "cl100k_base",
    "gpt-3.5": "cl100k_base",
    "gpt-35-turbo": "cl100k_base",
    "davinci-002": "cl100k_base",
    "babbage-002": "cl100k_base",
    "text-embedding-ada-002": "cl100k_base",
    "text-embedding-3-small": "cl100k_base",
    "text-embedding-3-large": "cl100k_base",
    "text-davinci-003": "p50k_base",
    "text-davinci-002": "p50k_base",
    "text-davinci-001": "r50k_base",
    "text-curie-001": "r50k_base",
    "text-babbage-001": "r50k_base",
    "text-ada-001": "r50k_base",
    "davinci": "r50k_base",
    "curie": "r50k_base",
    "babbage": "r50k_base",
    "ada": "r50k_base",
    "code-davinci-002": "p50k_base",
    "code-davinci-001": "p50k_base",
    "code-cushman-002": "p50k_base",
    "code-cushman-001": "p50k_base",
    "davinci-codex": "p50k_base",
    "cushman-codex": "p50k_base",
    "text-davinci-edit-001": "p50k_edit",
    "code-davinci-edit-001": "p50k_edit",
    "text-similarity-davinci-001": "r50k_base",
    "text-similarity-curie-001": "r50k_base",
    "text-similarity-babbage-001": "r50k_base",
    "text-similarity-ada-001": "r50k_base",
    "text-search-davinci-doc-001": "r50k_base",
    "text-search-curie-doc-001": "r50k_base",
    "text-search-babbage-doc-001": "r50k_base",
    "text-search-ada-doc-001": "r50k_base",
    "code-search-babbage-code-001": "r50k_base",
    "code-search-ada-code-001": "r50k_base",
    "gpt2": "gpt2",
    "gpt-2": "r50k_base",
}


class EncodingSpec:
    __slots__ = ("name", "rank_file_url", "pat_str", "special_tokens", "explicit_n_vocab")

    name: str
    rank_file_url: str
    pat_str: str
    special_tokens: dict[str, int]
    explicit_n_vocab: int

    def __init__(
        self,
        *,
        name: str,
        rank_file_url: str,
        pat_str: str,
        special_tokens: dict[str, int],
        explicit_n_vocab: int,
    ) -> None:
        self.name = name
        self.rank_file_url = rank_file_url
        self.pat_str = pat_str
        self.special_tokens = special_tokens
        self.explicit_n_vocab = explicit_n_vocab

    @property
    def n_vocab(self) -> int:
        return self.explicit_n_vocab

    @property
    def eot_token(self) -> int:
        return self.special_tokens[ENDOFTEXT]


_ENCODING_SPECS = {
    "o200k_base": EncodingSpec(
        name="o200k_base",
        rank_file_url="https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        pat_str=_O200K_PAT_STR,
        special_tokens={ENDOFTEXT: 199999, ENDOFPROMPT: 200018},
        explicit_n_vocab=200019,
    ),
    "cl100k_base": EncodingSpec(
        name="cl100k_base",
        rank_file_url="https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
        pat_str=_CL100K_PAT_STR,
        special_tokens={
            ENDOFTEXT: 100257,
            FIM_PREFIX: 100258,
            FIM_MIDDLE: 100259,
            FIM_SUFFIX: 100260,
            ENDOFPROMPT: 100276,
        },
        explicit_n_vocab=100277,
    ),
    "p50k_base": EncodingSpec(
        name="p50k_base",
        rank_file_url="https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
        pat_str=_R50K_PAT_STR,
        special_tokens={ENDOFTEXT: 50256},
        explicit_n_vocab=50281,
    ),
    "r50k_base": EncodingSpec(
        name="r50k_base",
        rank_file_url="https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
        pat_str=_R50K_PAT_STR,
        special_tokens={ENDOFTEXT: 50256},
        explicit_n_vocab=50257,
    ),
    "gpt2": EncodingSpec(
        name="gpt2",
        rank_file_url="https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
        pat_str=_R50K_PAT_STR,
        special_tokens={ENDOFTEXT: 50256},
        explicit_n_vocab=50257,
    ),
    "p50k_edit": EncodingSpec(
        name="p50k_edit",
        rank_file_url="https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
        pat_str=_R50K_PAT_STR,
        special_tokens={ENDOFTEXT: 50256},
        explicit_n_vocab=50281,
    ),
    "o200k_harmony": EncodingSpec(
        name="o200k_harmony",
        rank_file_url="https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        pat_str=_O200K_PAT_STR,
        special_tokens={ENDOFTEXT: 199999, ENDOFPROMPT: 200018},
        explicit_n_vocab=200019,
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
    if model in _MODEL_TO_ENCODING:
        return _MODEL_TO_ENCODING[model]

    for prefix, encoding_name in _MODEL_PREFIX_TO_ENCODING.items():
        if model.startswith(prefix):
            return encoding_name

    raise KeyError(
        f"Could not automatically map {model!r} to an encoding. "
        "Use get_encoding(name) to select one explicitly."
    )
