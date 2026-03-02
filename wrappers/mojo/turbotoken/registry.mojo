from collections import Dict, List
from .error import TurbotokenError


@value
struct EncodingSpec(Stringable):
    var name: String
    var rank_file_url: String
    var pat_str: String
    var n_vocab: Int

    fn __str__(self) -> String:
        return "EncodingSpec(" + self.name + ", n_vocab=" + str(self.n_vocab) + ")"


fn _r50k_pat_str() -> String:
    return "'(?:[sdmt]|ll|ve|re)| ?\\p{L}++| ?\\p{N}++| ?[^\\s\\p{L}\\p{N}]++|\\s++$|\\s+(?!\\S)|\\s"


fn _cl100k_pat_str() -> String:
    return "'(?i:[sdmt]|ll|ve|re)|[^\\r\\n\\p{L}\\p{N}]?+\\p{L}++|\\p{N}{1,3}+| ?[^\\s\\p{L}\\p{N}]++[\\r\\n]*+|\\s++$|\\s*[\\r\\n]|\\s+(?!\\S)|\\s"


fn _o200k_pat_str() -> String:
    return (
        "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]*[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?"
        + "|[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]+[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?"
        + "|\\p{N}{1,3}"
        + "| ?[^\\s\\p{L}\\p{N}]+[\\r\\n/]*"
        + "|\\s*[\\r\\n]+"
        + "|\\s+(?!\\S)"
        + "|\\s+"
    )


fn get_encoding_spec(name: String) raises -> EncodingSpec:
    if name == "o200k_base":
        return EncodingSpec(
            name="o200k_base",
            rank_file_url="https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
            pat_str=_o200k_pat_str(),
            n_vocab=200019,
        )
    elif name == "cl100k_base":
        return EncodingSpec(
            name="cl100k_base",
            rank_file_url="https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
            pat_str=_cl100k_pat_str(),
            n_vocab=100277,
        )
    elif name == "p50k_base":
        return EncodingSpec(
            name="p50k_base",
            rank_file_url="https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
            pat_str=_r50k_pat_str(),
            n_vocab=50281,
        )
    elif name == "r50k_base":
        return EncodingSpec(
            name="r50k_base",
            rank_file_url="https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
            pat_str=_r50k_pat_str(),
            n_vocab=50257,
        )
    elif name == "gpt2":
        return EncodingSpec(
            name="gpt2",
            rank_file_url="https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
            pat_str=_r50k_pat_str(),
            n_vocab=50257,
        )
    elif name == "p50k_edit":
        return EncodingSpec(
            name="p50k_edit",
            rank_file_url="https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
            pat_str=_r50k_pat_str(),
            n_vocab=50281,
        )
    elif name == "o200k_harmony":
        return EncodingSpec(
            name="o200k_harmony",
            rank_file_url="https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
            pat_str=_o200k_pat_str(),
            n_vocab=200019,
        )
    else:
        raise Error("Unknown encoding '" + name + "'. Supported: cl100k_base, gpt2, o200k_base, o200k_harmony, p50k_base, p50k_edit, r50k_base")


fn model_to_encoding(model: String) raises -> String:
    # Exact matches
    if model == "o1": return "o200k_base"
    if model == "o3": return "o200k_base"
    if model == "o4-mini": return "o200k_base"
    if model == "gpt-5": return "o200k_base"
    if model == "gpt-4.1": return "o200k_base"
    if model == "gpt-4o": return "o200k_base"
    if model == "gpt-4o-mini": return "o200k_base"
    if model == "gpt-4.1-mini": return "o200k_base"
    if model == "gpt-4.1-nano": return "o200k_base"
    if model == "gpt-oss-120b": return "o200k_harmony"
    if model == "gpt-4": return "cl100k_base"
    if model == "gpt-3.5-turbo": return "cl100k_base"
    if model == "gpt-3.5": return "cl100k_base"
    if model == "gpt-35-turbo": return "cl100k_base"
    if model == "davinci-002": return "cl100k_base"
    if model == "babbage-002": return "cl100k_base"
    if model == "text-embedding-ada-002": return "cl100k_base"
    if model == "text-embedding-3-small": return "cl100k_base"
    if model == "text-embedding-3-large": return "cl100k_base"
    if model == "text-davinci-003": return "p50k_base"
    if model == "text-davinci-002": return "p50k_base"
    if model == "text-davinci-001": return "r50k_base"
    if model == "text-curie-001": return "r50k_base"
    if model == "text-babbage-001": return "r50k_base"
    if model == "text-ada-001": return "r50k_base"
    if model == "davinci": return "r50k_base"
    if model == "curie": return "r50k_base"
    if model == "babbage": return "r50k_base"
    if model == "ada": return "r50k_base"
    if model == "code-davinci-002": return "p50k_base"
    if model == "code-davinci-001": return "p50k_base"
    if model == "code-cushman-002": return "p50k_base"
    if model == "code-cushman-001": return "p50k_base"
    if model == "davinci-codex": return "p50k_base"
    if model == "cushman-codex": return "p50k_base"
    if model == "text-davinci-edit-001": return "p50k_edit"
    if model == "code-davinci-edit-001": return "p50k_edit"
    if model == "text-similarity-davinci-001": return "r50k_base"
    if model == "text-similarity-curie-001": return "r50k_base"
    if model == "text-similarity-babbage-001": return "r50k_base"
    if model == "text-similarity-ada-001": return "r50k_base"
    if model == "text-search-davinci-doc-001": return "r50k_base"
    if model == "text-search-curie-doc-001": return "r50k_base"
    if model == "text-search-babbage-doc-001": return "r50k_base"
    if model == "text-search-ada-doc-001": return "r50k_base"
    if model == "code-search-babbage-code-001": return "r50k_base"
    if model == "code-search-ada-code-001": return "r50k_base"
    if model == "gpt2": return "gpt2"
    if model == "gpt-2": return "r50k_base"

    # Prefix matches
    if model.startswith("o1-"): return "o200k_base"
    if model.startswith("o3-"): return "o200k_base"
    if model.startswith("o4-mini-"): return "o200k_base"
    if model.startswith("gpt-5-"): return "o200k_base"
    if model.startswith("gpt-4.5-"): return "o200k_base"
    if model.startswith("gpt-4.1-"): return "o200k_base"
    if model.startswith("chatgpt-4o-"): return "o200k_base"
    if model.startswith("gpt-4o-"): return "o200k_base"
    if model.startswith("gpt-oss-"): return "o200k_harmony"
    if model.startswith("gpt-4-"): return "cl100k_base"
    if model.startswith("gpt-3.5-turbo-"): return "cl100k_base"
    if model.startswith("gpt-35-turbo-"): return "cl100k_base"
    if model.startswith("ft:gpt-4o"): return "o200k_base"
    if model.startswith("ft:gpt-4"): return "cl100k_base"
    if model.startswith("ft:gpt-3.5-turbo"): return "cl100k_base"
    if model.startswith("ft:davinci-002"): return "cl100k_base"
    if model.startswith("ft:babbage-002"): return "cl100k_base"

    raise Error(
        "Could not automatically map '" + model + "' to an encoding. "
        + "Use get_encoding(name) to select one explicitly."
    )


fn list_encoding_names() -> List[String]:
    var names = List[String]()
    names.append("cl100k_base")
    names.append("gpt2")
    names.append("o200k_base")
    names.append("o200k_harmony")
    names.append("p50k_base")
    names.append("p50k_edit")
    names.append("r50k_base")
    return names
