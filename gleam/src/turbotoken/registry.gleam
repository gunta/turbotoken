/// Encoding specifications and model-to-encoding mapping.
/// Mirrors the Python turbotoken._registry module.

import gleam/dict.{type Dict}
import gleam/list
import gleam/string

/// Specification for an encoding.
pub type EncodingSpec {
  EncodingSpec(
    name: String,
    rank_file_url: String,
    pat_str: String,
    special_tokens: Dict(String, Int),
    explicit_n_vocab: Int,
  )
}

/// Build the encoding specs map.
pub fn encoding_specs() -> Dict(String, EncodingSpec) {
  let r50k_pat =
    "'(?:[sdmt]|ll|ve|re)| ?\\p{L}++| ?\\p{N}++| ?[^\\s\\p{L}\\p{N}]++|\\s++$|\\s+(?!\\S)|\\s"
  let cl100k_pat =
    "'(?i:[sdmt]|ll|ve|re)|[^\\r\\n\\p{L}\\p{N}]?+\\p{L}++|\\p{N}{1,3}+| ?[^\\s\\p{L}\\p{N}]++[\\r\\n]*+|\\s++$|\\s*[\\r\\n]|\\s+(?!\\S)|\\s"
  let o200k_pat =
    string.join(
      [
        "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]*[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
        "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]+[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
        "\\p{N}{1,3}",
        " ?[^\\s\\p{L}\\p{N}]+[\\r\\n/]*",
        "\\s*[\\r\\n]+",
        "\\s+(?!\\S)",
        "\\s+",
      ],
      "|",
    )

  dict.from_list([
    #(
      "o200k_base",
      EncodingSpec(
        name: "o200k_base",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        pat_str: o200k_pat,
        special_tokens: dict.from_list([
          #("<|endoftext|>", 199_999),
          #("<|endofprompt|>", 200_018),
        ]),
        explicit_n_vocab: 200_019,
      ),
    ),
    #(
      "cl100k_base",
      EncodingSpec(
        name: "cl100k_base",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
        pat_str: cl100k_pat,
        special_tokens: dict.from_list([
          #("<|endoftext|>", 100_257),
          #("<|fim_prefix|>", 100_258),
          #("<|fim_middle|>", 100_259),
          #("<|fim_suffix|>", 100_260),
          #("<|endofprompt|>", 100_276),
        ]),
        explicit_n_vocab: 100_277,
      ),
    ),
    #(
      "p50k_base",
      EncodingSpec(
        name: "p50k_base",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
        pat_str: r50k_pat,
        special_tokens: dict.from_list([#("<|endoftext|>", 50_256)]),
        explicit_n_vocab: 50_281,
      ),
    ),
    #(
      "r50k_base",
      EncodingSpec(
        name: "r50k_base",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
        pat_str: r50k_pat,
        special_tokens: dict.from_list([#("<|endoftext|>", 50_256)]),
        explicit_n_vocab: 50_257,
      ),
    ),
    #(
      "gpt2",
      EncodingSpec(
        name: "gpt2",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
        pat_str: r50k_pat,
        special_tokens: dict.from_list([#("<|endoftext|>", 50_256)]),
        explicit_n_vocab: 50_257,
      ),
    ),
    #(
      "p50k_edit",
      EncodingSpec(
        name: "p50k_edit",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
        pat_str: r50k_pat,
        special_tokens: dict.from_list([#("<|endoftext|>", 50_256)]),
        explicit_n_vocab: 50_281,
      ),
    ),
    #(
      "o200k_harmony",
      EncodingSpec(
        name: "o200k_harmony",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        pat_str: o200k_pat,
        special_tokens: dict.from_list([
          #("<|endoftext|>", 199_999),
          #("<|endofprompt|>", 200_018),
        ]),
        explicit_n_vocab: 200_019,
      ),
    ),
  ])
}

/// Model name to encoding name map.
fn model_to_encoding_map() -> Dict(String, String) {
  dict.from_list([
    #("o1", "o200k_base"),
    #("o3", "o200k_base"),
    #("o4-mini", "o200k_base"),
    #("gpt-5", "o200k_base"),
    #("gpt-4.1", "o200k_base"),
    #("gpt-4o", "o200k_base"),
    #("gpt-4o-mini", "o200k_base"),
    #("gpt-4.1-mini", "o200k_base"),
    #("gpt-4.1-nano", "o200k_base"),
    #("gpt-oss-120b", "o200k_harmony"),
    #("gpt-4", "cl100k_base"),
    #("gpt-3.5-turbo", "cl100k_base"),
    #("gpt-3.5", "cl100k_base"),
    #("gpt-35-turbo", "cl100k_base"),
    #("davinci-002", "cl100k_base"),
    #("babbage-002", "cl100k_base"),
    #("text-embedding-ada-002", "cl100k_base"),
    #("text-embedding-3-small", "cl100k_base"),
    #("text-embedding-3-large", "cl100k_base"),
    #("text-davinci-003", "p50k_base"),
    #("text-davinci-002", "p50k_base"),
    #("text-davinci-001", "r50k_base"),
    #("text-curie-001", "r50k_base"),
    #("text-babbage-001", "r50k_base"),
    #("text-ada-001", "r50k_base"),
    #("davinci", "r50k_base"),
    #("curie", "r50k_base"),
    #("babbage", "r50k_base"),
    #("ada", "r50k_base"),
    #("code-davinci-002", "p50k_base"),
    #("code-davinci-001", "p50k_base"),
    #("code-cushman-002", "p50k_base"),
    #("code-cushman-001", "p50k_base"),
    #("davinci-codex", "p50k_base"),
    #("cushman-codex", "p50k_base"),
    #("text-davinci-edit-001", "p50k_edit"),
    #("code-davinci-edit-001", "p50k_edit"),
    #("text-similarity-davinci-001", "r50k_base"),
    #("text-similarity-curie-001", "r50k_base"),
    #("text-similarity-babbage-001", "r50k_base"),
    #("text-similarity-ada-001", "r50k_base"),
    #("text-search-davinci-doc-001", "r50k_base"),
    #("text-search-curie-doc-001", "r50k_base"),
    #("text-search-babbage-doc-001", "r50k_base"),
    #("text-search-ada-doc-001", "r50k_base"),
    #("code-search-babbage-code-001", "r50k_base"),
    #("code-search-ada-code-001", "r50k_base"),
    #("gpt2", "gpt2"),
    #("gpt-2", "r50k_base"),
  ])
}

/// Model prefix to encoding mapping for fallback matching.
fn model_prefix_to_encoding_list() -> List(#(String, String)) {
  [
    #("o1-", "o200k_base"),
    #("o3-", "o200k_base"),
    #("o4-mini-", "o200k_base"),
    #("gpt-5-", "o200k_base"),
    #("gpt-4.5-", "o200k_base"),
    #("gpt-4.1-", "o200k_base"),
    #("chatgpt-4o-", "o200k_base"),
    #("gpt-4o-", "o200k_base"),
    #("gpt-oss-", "o200k_harmony"),
    #("gpt-4-", "cl100k_base"),
    #("gpt-3.5-turbo-", "cl100k_base"),
    #("gpt-35-turbo-", "cl100k_base"),
    #("ft:gpt-4o", "o200k_base"),
    #("ft:gpt-4", "cl100k_base"),
    #("ft:gpt-3.5-turbo", "cl100k_base"),
    #("ft:davinci-002", "cl100k_base"),
    #("ft:babbage-002", "cl100k_base"),
  ]
}

/// Get the encoding spec for a given encoding name.
pub fn get_encoding_spec(
  name: String,
) -> Result(EncodingSpec, String) {
  case dict.get(encoding_specs(), name) {
    Ok(spec) -> Ok(spec)
    Error(_) -> Error("Unknown encoding: " <> name)
  }
}

/// Map a model name to an encoding name.
pub fn model_to_encoding(
  model: String,
) -> Result(String, String) {
  case dict.get(model_to_encoding_map(), model) {
    Ok(enc) -> Ok(enc)
    Error(_) -> model_prefix_lookup(model, model_prefix_to_encoding_list())
  }
}

fn model_prefix_lookup(
  model: String,
  prefixes: List(#(String, String)),
) -> Result(String, String) {
  case prefixes {
    [] -> Error("Unknown model: " <> model)
    [#(prefix, enc), ..rest] ->
      case string.starts_with(model, prefix) {
        True -> Ok(enc)
        False -> model_prefix_lookup(model, rest)
      }
  }
}

/// List all supported encoding names (sorted).
pub fn list_encoding_names() -> List(String) {
  encoding_specs()
  |> dict.keys()
  |> list.sort(string.compare)
}
