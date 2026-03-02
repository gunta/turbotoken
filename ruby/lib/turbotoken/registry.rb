module TurboToken
  module Registry
    ENDOFTEXT = "<|endoftext|>"
    FIM_PREFIX = "<|fim_prefix|>"
    FIM_MIDDLE = "<|fim_middle|>"
    FIM_SUFFIX = "<|fim_suffix|>"
    ENDOFPROMPT = "<|endofprompt|>"

    EncodingSpec = Struct.new(:name, :rank_file_url, :pat_str, :special_tokens, :explicit_n_vocab, keyword_init: true)

    R50K_PAT_STR = "'(?:[sdmt]|ll|ve|re)| ?\\p{L}++| ?\\p{N}++| ?[^\\s\\p{L}\\p{N}]++|\\s++$|\\s+(?!\\S)|\\s"

    CL100K_PAT_STR = "'(?i:[sdmt]|ll|ve|re)|[^\\r\\n\\p{L}\\p{N}]?+\\p{L}++|\\p{N}{1,3}+| ?[^\\s\\p{L}\\p{N}]++[\\r\\n]*+|\\s++$|\\s*[\\r\\n]|\\s+(?!\\S)|\\s"

    O200K_PAT_STR = [
      "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]*[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
      "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]+[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
      "\\p{N}{1,3}",
      " ?[^\\s\\p{L}\\p{N}]+[\\r\\n/]*",
      "\\s*[\\r\\n]+",
      "\\s+(?!\\S)",
      "\\s+",
    ].join("|").freeze

    ENCODING_SPECS = {
      "o200k_base" => EncodingSpec.new(
        name: "o200k_base",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        pat_str: O200K_PAT_STR,
        special_tokens: { ENDOFTEXT => 199_999, ENDOFPROMPT => 200_018 },
        explicit_n_vocab: 200_019,
      ),
      "cl100k_base" => EncodingSpec.new(
        name: "cl100k_base",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
        pat_str: CL100K_PAT_STR,
        special_tokens: {
          ENDOFTEXT => 100_257,
          FIM_PREFIX => 100_258,
          FIM_MIDDLE => 100_259,
          FIM_SUFFIX => 100_260,
          ENDOFPROMPT => 100_276,
        },
        explicit_n_vocab: 100_277,
      ),
      "p50k_base" => EncodingSpec.new(
        name: "p50k_base",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
        pat_str: R50K_PAT_STR,
        special_tokens: { ENDOFTEXT => 50_256 },
        explicit_n_vocab: 50_281,
      ),
      "r50k_base" => EncodingSpec.new(
        name: "r50k_base",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
        pat_str: R50K_PAT_STR,
        special_tokens: { ENDOFTEXT => 50_256 },
        explicit_n_vocab: 50_257,
      ),
      "gpt2" => EncodingSpec.new(
        name: "gpt2",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
        pat_str: R50K_PAT_STR,
        special_tokens: { ENDOFTEXT => 50_256 },
        explicit_n_vocab: 50_257,
      ),
      "p50k_edit" => EncodingSpec.new(
        name: "p50k_edit",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
        pat_str: R50K_PAT_STR,
        special_tokens: { ENDOFTEXT => 50_256 },
        explicit_n_vocab: 50_281,
      ),
      "o200k_harmony" => EncodingSpec.new(
        name: "o200k_harmony",
        rank_file_url: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        pat_str: O200K_PAT_STR,
        special_tokens: { ENDOFTEXT => 199_999, ENDOFPROMPT => 200_018 },
        explicit_n_vocab: 200_019,
      ),
    }.freeze

    MODEL_TO_ENCODING = {
      "o1" => "o200k_base",
      "o3" => "o200k_base",
      "o4-mini" => "o200k_base",
      "gpt-5" => "o200k_base",
      "gpt-4.1" => "o200k_base",
      "gpt-4o" => "o200k_base",
      "gpt-4o-mini" => "o200k_base",
      "gpt-4.1-mini" => "o200k_base",
      "gpt-4.1-nano" => "o200k_base",
      "gpt-oss-120b" => "o200k_harmony",
      "gpt-4" => "cl100k_base",
      "gpt-3.5-turbo" => "cl100k_base",
      "gpt-3.5" => "cl100k_base",
      "gpt-35-turbo" => "cl100k_base",
      "davinci-002" => "cl100k_base",
      "babbage-002" => "cl100k_base",
      "text-embedding-ada-002" => "cl100k_base",
      "text-embedding-3-small" => "cl100k_base",
      "text-embedding-3-large" => "cl100k_base",
      "text-davinci-003" => "p50k_base",
      "text-davinci-002" => "p50k_base",
      "text-davinci-001" => "r50k_base",
      "text-curie-001" => "r50k_base",
      "text-babbage-001" => "r50k_base",
      "text-ada-001" => "r50k_base",
      "davinci" => "r50k_base",
      "curie" => "r50k_base",
      "babbage" => "r50k_base",
      "ada" => "r50k_base",
      "code-davinci-002" => "p50k_base",
      "code-davinci-001" => "p50k_base",
      "code-cushman-002" => "p50k_base",
      "code-cushman-001" => "p50k_base",
      "davinci-codex" => "p50k_base",
      "cushman-codex" => "p50k_base",
      "text-davinci-edit-001" => "p50k_edit",
      "code-davinci-edit-001" => "p50k_edit",
      "text-similarity-davinci-001" => "r50k_base",
      "text-similarity-curie-001" => "r50k_base",
      "text-similarity-babbage-001" => "r50k_base",
      "text-similarity-ada-001" => "r50k_base",
      "text-search-davinci-doc-001" => "r50k_base",
      "text-search-curie-doc-001" => "r50k_base",
      "text-search-babbage-doc-001" => "r50k_base",
      "text-search-ada-doc-001" => "r50k_base",
      "code-search-babbage-code-001" => "r50k_base",
      "code-search-ada-code-001" => "r50k_base",
      "gpt2" => "gpt2",
      "gpt-2" => "r50k_base",
    }.freeze

    MODEL_PREFIX_TO_ENCODING = [
      ["o1-", "o200k_base"],
      ["o3-", "o200k_base"],
      ["o4-mini-", "o200k_base"],
      ["gpt-5-", "o200k_base"],
      ["gpt-4.5-", "o200k_base"],
      ["gpt-4.1-", "o200k_base"],
      ["chatgpt-4o-", "o200k_base"],
      ["gpt-4o-", "o200k_base"],
      ["gpt-oss-", "o200k_harmony"],
      ["gpt-4-", "cl100k_base"],
      ["gpt-3.5-turbo-", "cl100k_base"],
      ["gpt-35-turbo-", "cl100k_base"],
      ["ft:gpt-4o", "o200k_base"],
      ["ft:gpt-4", "cl100k_base"],
      ["ft:gpt-3.5-turbo", "cl100k_base"],
      ["ft:davinci-002", "cl100k_base"],
      ["ft:babbage-002", "cl100k_base"],
    ].freeze

    def self.get_encoding_spec(name)
      spec = ENCODING_SPECS[name]
      raise Error, "Unknown encoding #{name.inspect}. Supported: #{list_encoding_names.join(', ')}" unless spec
      spec
    end

    def self.model_to_encoding(model)
      enc = MODEL_TO_ENCODING[model]
      return enc if enc

      MODEL_PREFIX_TO_ENCODING.each do |prefix, encoding_name|
        return encoding_name if model.start_with?(prefix)
      end

      raise Error, "Could not automatically map #{model.inspect} to an encoding. Use get_encoding(name) to select one explicitly."
    end

    def self.list_encoding_names
      ENCODING_SPECS.keys.sort
    end
  end
end
