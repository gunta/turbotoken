use std::collections::HashMap;
use std::sync::LazyLock;

use crate::error::TurbotokenError;

/// Specification for a BPE encoding (rank file URL, pattern, special tokens, vocab size).
#[derive(Debug, Clone)]
pub struct EncodingSpec {
    pub name: &'static str,
    pub rank_file_url: &'static str,
    pub pat_str: &'static str,
    pub special_tokens: HashMap<&'static str, u32>,
    pub n_vocab: usize,
}

// ── Pattern strings ──────────────────────────────────────────────────────

const R50K_PAT_STR: &str = r"'(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s";

const CL100K_PAT_STR: &str = r"'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s";

const O200K_PAT_STR: &str = concat!(
    r"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
    "|",
    r"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
    "|",
    r"\p{N}{1,3}",
    "|",
    r" ?[^\s\p{L}\p{N}]+[\r\n/]*",
    "|",
    r"\s*[\r\n]+",
    "|",
    r"\s+(?!\S)",
    "|",
    r"\s+",
);

// ── Special token constants ──────────────────────────────────────────────

const ENDOFTEXT: &str = "<|endoftext|>";
const FIM_PREFIX: &str = "<|fim_prefix|>";
const FIM_MIDDLE: &str = "<|fim_middle|>";
const FIM_SUFFIX: &str = "<|fim_suffix|>";
const ENDOFPROMPT: &str = "<|endofprompt|>";

// ── Encoding specs ───────────────────────────────────────────────────────

static ENCODING_SPECS: LazyLock<HashMap<&'static str, EncodingSpec>> = LazyLock::new(|| {
    let mut m = HashMap::new();

    m.insert("o200k_base", EncodingSpec {
        name: "o200k_base",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        pat_str: O200K_PAT_STR,
        special_tokens: HashMap::from([
            (ENDOFTEXT, 199999),
            (ENDOFPROMPT, 200018),
        ]),
        n_vocab: 200019,
    });

    m.insert("cl100k_base", EncodingSpec {
        name: "cl100k_base",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
        pat_str: CL100K_PAT_STR,
        special_tokens: HashMap::from([
            (ENDOFTEXT, 100257),
            (FIM_PREFIX, 100258),
            (FIM_MIDDLE, 100259),
            (FIM_SUFFIX, 100260),
            (ENDOFPROMPT, 100276),
        ]),
        n_vocab: 100277,
    });

    m.insert("p50k_base", EncodingSpec {
        name: "p50k_base",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
        pat_str: R50K_PAT_STR,
        special_tokens: HashMap::from([
            (ENDOFTEXT, 50256),
        ]),
        n_vocab: 50281,
    });

    m.insert("r50k_base", EncodingSpec {
        name: "r50k_base",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
        pat_str: R50K_PAT_STR,
        special_tokens: HashMap::from([
            (ENDOFTEXT, 50256),
        ]),
        n_vocab: 50257,
    });

    m.insert("gpt2", EncodingSpec {
        name: "gpt2",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
        pat_str: R50K_PAT_STR,
        special_tokens: HashMap::from([
            (ENDOFTEXT, 50256),
        ]),
        n_vocab: 50257,
    });

    m.insert("p50k_edit", EncodingSpec {
        name: "p50k_edit",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
        pat_str: R50K_PAT_STR,
        special_tokens: HashMap::from([
            (ENDOFTEXT, 50256),
        ]),
        n_vocab: 50281,
    });

    m.insert("o200k_harmony", EncodingSpec {
        name: "o200k_harmony",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        pat_str: O200K_PAT_STR,
        special_tokens: HashMap::from([
            (ENDOFTEXT, 199999),
            (ENDOFPROMPT, 200018),
        ]),
        n_vocab: 200019,
    });

    m
});

// ── Model → encoding mappings ────────────────────────────────────────────

static MODEL_TO_ENCODING: LazyLock<HashMap<&'static str, &'static str>> = LazyLock::new(|| {
    HashMap::from([
        ("o1", "o200k_base"),
        ("o3", "o200k_base"),
        ("o4-mini", "o200k_base"),
        ("gpt-5", "o200k_base"),
        ("gpt-4.1", "o200k_base"),
        ("gpt-4o", "o200k_base"),
        ("gpt-4o-mini", "o200k_base"),
        ("gpt-4.1-mini", "o200k_base"),
        ("gpt-4.1-nano", "o200k_base"),
        ("gpt-oss-120b", "o200k_harmony"),
        ("gpt-4", "cl100k_base"),
        ("gpt-3.5-turbo", "cl100k_base"),
        ("gpt-3.5", "cl100k_base"),
        ("gpt-35-turbo", "cl100k_base"),
        ("davinci-002", "cl100k_base"),
        ("babbage-002", "cl100k_base"),
        ("text-embedding-ada-002", "cl100k_base"),
        ("text-embedding-3-small", "cl100k_base"),
        ("text-embedding-3-large", "cl100k_base"),
        ("text-davinci-003", "p50k_base"),
        ("text-davinci-002", "p50k_base"),
        ("text-davinci-001", "r50k_base"),
        ("text-curie-001", "r50k_base"),
        ("text-babbage-001", "r50k_base"),
        ("text-ada-001", "r50k_base"),
        ("davinci", "r50k_base"),
        ("curie", "r50k_base"),
        ("babbage", "r50k_base"),
        ("ada", "r50k_base"),
        ("code-davinci-002", "p50k_base"),
        ("code-davinci-001", "p50k_base"),
        ("code-cushman-002", "p50k_base"),
        ("code-cushman-001", "p50k_base"),
        ("davinci-codex", "p50k_base"),
        ("cushman-codex", "p50k_base"),
        ("text-davinci-edit-001", "p50k_edit"),
        ("code-davinci-edit-001", "p50k_edit"),
        ("text-similarity-davinci-001", "r50k_base"),
        ("text-similarity-curie-001", "r50k_base"),
        ("text-similarity-babbage-001", "r50k_base"),
        ("text-similarity-ada-001", "r50k_base"),
        ("text-search-davinci-doc-001", "r50k_base"),
        ("text-search-curie-doc-001", "r50k_base"),
        ("text-search-babbage-doc-001", "r50k_base"),
        ("text-search-ada-doc-001", "r50k_base"),
        ("code-search-babbage-code-001", "r50k_base"),
        ("code-search-ada-code-001", "r50k_base"),
        ("gpt2", "gpt2"),
        ("gpt-2", "r50k_base"),
    ])
});

static MODEL_PREFIX_TO_ENCODING: LazyLock<Vec<(&'static str, &'static str)>> = LazyLock::new(|| {
    vec![
        ("o1-", "o200k_base"),
        ("o3-", "o200k_base"),
        ("o4-mini-", "o200k_base"),
        ("gpt-5-", "o200k_base"),
        ("gpt-4.5-", "o200k_base"),
        ("gpt-4.1-", "o200k_base"),
        ("chatgpt-4o-", "o200k_base"),
        ("gpt-4o-", "o200k_base"),
        ("gpt-oss-", "o200k_harmony"),
        ("gpt-4-", "cl100k_base"),
        ("gpt-3.5-turbo-", "cl100k_base"),
        ("gpt-35-turbo-", "cl100k_base"),
        ("ft:gpt-4o", "o200k_base"),
        ("ft:gpt-4", "cl100k_base"),
        ("ft:gpt-3.5-turbo", "cl100k_base"),
        ("ft:davinci-002", "cl100k_base"),
        ("ft:babbage-002", "cl100k_base"),
    ]
});

// ── Public API ───────────────────────────────────────────────────────────

/// Look up an encoding spec by name.
pub fn get_encoding_spec(name: &str) -> Result<&'static EncodingSpec, TurbotokenError> {
    ENCODING_SPECS.get(name).ok_or_else(|| {
        let supported: Vec<&str> = list_encoding_names().into_iter().collect();
        TurbotokenError::InvalidEncoding(format!(
            "Unknown encoding {name:?}. Supported: {}",
            supported.join(", ")
        ))
    })
}

/// Map a model name to its encoding name.
pub fn model_to_encoding(model: &str) -> Result<String, TurbotokenError> {
    if let Some(&enc) = MODEL_TO_ENCODING.get(model) {
        return Ok(enc.to_string());
    }

    for &(prefix, enc) in MODEL_PREFIX_TO_ENCODING.iter() {
        if model.starts_with(prefix) {
            return Ok(enc.to_string());
        }
    }

    Err(TurbotokenError::InvalidEncoding(format!(
        "Could not automatically map {model:?} to an encoding. \
         Use get_encoding(name) to select one explicitly."
    )))
}

/// Return a sorted list of all supported encoding names.
pub fn list_encoding_names() -> Vec<&'static str> {
    let mut names: Vec<&str> = ENCODING_SPECS.keys().copied().collect();
    names.sort();
    names
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_list_encodings() {
        let names = list_encoding_names();
        assert!(names.contains(&"o200k_base"));
        assert!(names.contains(&"cl100k_base"));
        assert!(names.contains(&"gpt2"));
        assert_eq!(names.len(), 7);
    }

    #[test]
    fn test_get_encoding_spec() {
        let spec = get_encoding_spec("o200k_base").unwrap();
        assert_eq!(spec.n_vocab, 200019);
        assert_eq!(spec.special_tokens[ENDOFTEXT], 199999);
    }

    #[test]
    fn test_model_to_encoding() {
        assert_eq!(model_to_encoding("gpt-4o").unwrap(), "o200k_base");
        assert_eq!(model_to_encoding("gpt-4").unwrap(), "cl100k_base");
        assert_eq!(model_to_encoding("gpt-4o-2024-08-06").unwrap(), "o200k_base");
        assert_eq!(model_to_encoding("ft:gpt-4o:org:custom").unwrap(), "o200k_base");
        assert!(model_to_encoding("nonexistent-model").is_err());
    }

    #[test]
    fn test_unknown_encoding() {
        assert!(get_encoding_spec("nonexistent").is_err());
    }
}
