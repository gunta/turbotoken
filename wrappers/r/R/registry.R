# Encoding specifications -- exact match to Python _registry.py

.r50k_pat_str <- "'(?:[sdmt]|ll|ve|re)| ?\\p{L}++| ?\\p{N}++| ?[^\\s\\p{L}\\p{N}]++|\\s++$|\\s+(?!\\S)|\\s"

.cl100k_pat_str <- "'(?i:[sdmt]|ll|ve|re)|[^\\r\\n\\p{L}\\p{N}]?+\\p{L}++|\\p{N}{1,3}+| ?[^\\s\\p{L}\\p{N}]++[\\r\\n]*+|\\s++$|\\s*[\\r\\n]|\\s+(?!\\S)|\\s"

.o200k_pat_str <- paste(
  "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]*[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
  "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]+[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
  "\\p{N}{1,3}",
  " ?[^\\s\\p{L}\\p{N}]+[\\r\\n/]*",
  "\\s*[\\r\\n]+",
  "\\s+(?!\\S)",
  "\\s+",
  sep = "|"
)

.encoding_specs <- list(
  o200k_base = list(
    name = "o200k_base",
    rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
    pat_str = .o200k_pat_str,
    special_tokens = list("<|endoftext|>" = 199999L, "<|endofprompt|>" = 200018L),
    n_vocab = 200019L
  ),
  cl100k_base = list(
    name = "cl100k_base",
    rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
    pat_str = .cl100k_pat_str,
    special_tokens = list(
      "<|endoftext|>" = 100257L,
      "<|fim_prefix|>" = 100258L,
      "<|fim_middle|>" = 100259L,
      "<|fim_suffix|>" = 100260L,
      "<|endofprompt|>" = 100276L
    ),
    n_vocab = 100277L
  ),
  p50k_base = list(
    name = "p50k_base",
    rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
    pat_str = .r50k_pat_str,
    special_tokens = list("<|endoftext|>" = 50256L),
    n_vocab = 50281L
  ),
  r50k_base = list(
    name = "r50k_base",
    rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
    pat_str = .r50k_pat_str,
    special_tokens = list("<|endoftext|>" = 50256L),
    n_vocab = 50257L
  ),
  gpt2 = list(
    name = "gpt2",
    rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
    pat_str = .r50k_pat_str,
    special_tokens = list("<|endoftext|>" = 50256L),
    n_vocab = 50257L
  ),
  p50k_edit = list(
    name = "p50k_edit",
    rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
    pat_str = .r50k_pat_str,
    special_tokens = list("<|endoftext|>" = 50256L),
    n_vocab = 50281L
  ),
  o200k_harmony = list(
    name = "o200k_harmony",
    rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
    pat_str = .o200k_pat_str,
    special_tokens = list("<|endoftext|>" = 199999L, "<|endofprompt|>" = 200018L),
    n_vocab = 200019L
  )
)

.model_to_encoding <- c(
  "o1" = "o200k_base",
  "o3" = "o200k_base",
  "o4-mini" = "o200k_base",
  "gpt-5" = "o200k_base",
  "gpt-4.1" = "o200k_base",
  "gpt-4o" = "o200k_base",
  "gpt-4o-mini" = "o200k_base",
  "gpt-4.1-mini" = "o200k_base",
  "gpt-4.1-nano" = "o200k_base",
  "gpt-oss-120b" = "o200k_harmony",
  "gpt-4" = "cl100k_base",
  "gpt-3.5-turbo" = "cl100k_base",
  "gpt-3.5" = "cl100k_base",
  "gpt-35-turbo" = "cl100k_base",
  "davinci-002" = "cl100k_base",
  "babbage-002" = "cl100k_base",
  "text-embedding-ada-002" = "cl100k_base",
  "text-embedding-3-small" = "cl100k_base",
  "text-embedding-3-large" = "cl100k_base",
  "text-davinci-003" = "p50k_base",
  "text-davinci-002" = "p50k_base",
  "text-davinci-001" = "r50k_base",
  "text-curie-001" = "r50k_base",
  "text-babbage-001" = "r50k_base",
  "text-ada-001" = "r50k_base",
  "davinci" = "r50k_base",
  "curie" = "r50k_base",
  "babbage" = "r50k_base",
  "ada" = "r50k_base",
  "code-davinci-002" = "p50k_base",
  "code-davinci-001" = "p50k_base",
  "code-cushman-002" = "p50k_base",
  "code-cushman-001" = "p50k_base",
  "davinci-codex" = "p50k_base",
  "cushman-codex" = "p50k_base",
  "text-davinci-edit-001" = "p50k_edit",
  "code-davinci-edit-001" = "p50k_edit",
  "text-similarity-davinci-001" = "r50k_base",
  "text-similarity-curie-001" = "r50k_base",
  "text-similarity-babbage-001" = "r50k_base",
  "text-similarity-ada-001" = "r50k_base",
  "text-search-davinci-doc-001" = "r50k_base",
  "text-search-curie-doc-001" = "r50k_base",
  "text-search-babbage-doc-001" = "r50k_base",
  "text-search-ada-doc-001" = "r50k_base",
  "code-search-babbage-code-001" = "r50k_base",
  "code-search-ada-code-001" = "r50k_base",
  "gpt2" = "gpt2",
  "gpt-2" = "r50k_base"
)

.model_prefix_to_encoding <- c(
  "o1-" = "o200k_base",
  "o3-" = "o200k_base",
  "o4-mini-" = "o200k_base",
  "gpt-5-" = "o200k_base",
  "gpt-4.5-" = "o200k_base",
  "gpt-4.1-" = "o200k_base",
  "chatgpt-4o-" = "o200k_base",
  "gpt-4o-" = "o200k_base",
  "gpt-oss-" = "o200k_harmony",
  "gpt-4-" = "cl100k_base",
  "gpt-3.5-turbo-" = "cl100k_base",
  "gpt-35-turbo-" = "cl100k_base",
  "ft:gpt-4o" = "o200k_base",
  "ft:gpt-4" = "cl100k_base",
  "ft:gpt-3.5-turbo" = "cl100k_base",
  "ft:davinci-002" = "cl100k_base",
  "ft:babbage-002" = "cl100k_base"
)

#' Get encoding specification by name
#'
#' @param name Character string, encoding name.
#' @return A list with encoding specification fields.
#' @keywords internal
get_encoding_spec <- function(name) {
  spec <- .encoding_specs[[name]]
  if (is.null(spec)) {
    supported <- paste(sort(names(.encoding_specs)), collapse = ", ")
    stop(sprintf("Unknown encoding '%s'. Supported encodings: %s", name, supported),
         call. = FALSE)
  }
  spec
}

#' Map a model name to its encoding name
#'
#' @param model Character string, model name.
#' @return Character string, encoding name.
#' @keywords internal
model_to_encoding_name <- function(model) {
  # Exact match
  enc <- .model_to_encoding[model]
  if (!is.na(enc)) {
    return(unname(enc))
  }

  # Prefix match
  prefixes <- names(.model_prefix_to_encoding)
  for (prefix in prefixes) {
    if (startsWith(model, prefix)) {
      return(unname(.model_prefix_to_encoding[prefix]))
    }
  }

  stop(sprintf(
    "Could not automatically map '%s' to an encoding. Use get_encoding(name) to select one explicitly.",
    model
  ), call. = FALSE)
}

#' List all available encoding names
#'
#' @return A sorted character vector of encoding names.
#' @export
list_encoding_names <- function() {
  sort(names(.encoding_specs))
}
