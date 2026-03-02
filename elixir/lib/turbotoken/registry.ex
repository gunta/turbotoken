defmodule TurboToken.Registry do
  @moduledoc """
  Encoding specifications and model-to-encoding mapping.
  Mirrors the Python turbotoken._registry module.
  """

  @type encoding_spec :: %{
          name: String.t(),
          rank_file_url: String.t(),
          pat_str: String.t(),
          special_tokens: %{String.t() => non_neg_integer()},
          explicit_n_vocab: non_neg_integer()
        }

  @endoftext "<|endoftext|>"
  @fim_prefix "<|fim_prefix|>"
  @fim_middle "<|fim_middle|>"
  @fim_suffix "<|fim_suffix|>"
  @endofprompt "<|endofprompt|>"

  @r50k_pat_str ~S"'(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s"

  @cl100k_pat_str ~S"'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s"

  @o200k_pat_str Enum.join(
                   [
                     ~S"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
                     ~S"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
                     ~S"\p{N}{1,3}",
                     ~S" ?[^\s\p{L}\p{N}]+[\r\n/]*",
                     ~S"\s*[\r\n]+",
                     ~S"\s+(?!\S)",
                     ~S"\s+"
                   ],
                   "|"
                 )

  @encoding_specs %{
    "o200k_base" => %{
      name: "o200k_base",
      rank_file_url:
        "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
      pat_str: @o200k_pat_str,
      special_tokens: %{@endoftext => 199_999, @endofprompt => 200_018},
      explicit_n_vocab: 200_019
    },
    "cl100k_base" => %{
      name: "cl100k_base",
      rank_file_url:
        "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
      pat_str: @cl100k_pat_str,
      special_tokens: %{
        @endoftext => 100_257,
        @fim_prefix => 100_258,
        @fim_middle => 100_259,
        @fim_suffix => 100_260,
        @endofprompt => 100_276
      },
      explicit_n_vocab: 100_277
    },
    "p50k_base" => %{
      name: "p50k_base",
      rank_file_url:
        "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
      pat_str: @r50k_pat_str,
      special_tokens: %{@endoftext => 50_256},
      explicit_n_vocab: 50_281
    },
    "r50k_base" => %{
      name: "r50k_base",
      rank_file_url:
        "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
      pat_str: @r50k_pat_str,
      special_tokens: %{@endoftext => 50_256},
      explicit_n_vocab: 50_257
    },
    "gpt2" => %{
      name: "gpt2",
      rank_file_url:
        "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
      pat_str: @r50k_pat_str,
      special_tokens: %{@endoftext => 50_256},
      explicit_n_vocab: 50_257
    },
    "p50k_edit" => %{
      name: "p50k_edit",
      rank_file_url:
        "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
      pat_str: @r50k_pat_str,
      special_tokens: %{@endoftext => 50_256},
      explicit_n_vocab: 50_281
    },
    "o200k_harmony" => %{
      name: "o200k_harmony",
      rank_file_url:
        "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
      pat_str: @o200k_pat_str,
      special_tokens: %{@endoftext => 199_999, @endofprompt => 200_018},
      explicit_n_vocab: 200_019
    }
  }

  @model_to_encoding %{
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
    "gpt-2" => "r50k_base"
  }

  @model_prefix_to_encoding [
    {"o1-", "o200k_base"},
    {"o3-", "o200k_base"},
    {"o4-mini-", "o200k_base"},
    {"gpt-5-", "o200k_base"},
    {"gpt-4.5-", "o200k_base"},
    {"gpt-4.1-", "o200k_base"},
    {"chatgpt-4o-", "o200k_base"},
    {"gpt-4o-", "o200k_base"},
    {"gpt-oss-", "o200k_harmony"},
    {"gpt-4-", "cl100k_base"},
    {"gpt-3.5-turbo-", "cl100k_base"},
    {"gpt-35-turbo-", "cl100k_base"},
    {"ft:gpt-4o", "o200k_base"},
    {"ft:gpt-4", "cl100k_base"},
    {"ft:gpt-3.5-turbo", "cl100k_base"},
    {"ft:davinci-002", "cl100k_base"},
    {"ft:babbage-002", "cl100k_base"}
  ]

  @spec get_encoding_spec(String.t()) :: {:ok, encoding_spec()} | {:error, term()}
  def get_encoding_spec(name) do
    case Map.fetch(@encoding_specs, name) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, {:unknown_encoding, name, list_encoding_names()}}
    end
  end

  @spec model_to_encoding(String.t()) :: {:ok, String.t()} | {:error, term()}
  def model_to_encoding(model) do
    case Map.fetch(@model_to_encoding, model) do
      {:ok, enc} ->
        {:ok, enc}

      :error ->
        case Enum.find(@model_prefix_to_encoding, fn {prefix, _} ->
               String.starts_with?(model, prefix)
             end) do
          {_, enc} -> {:ok, enc}
          nil -> {:error, {:unknown_model, model}}
        end
    end
  end

  @spec list_encoding_names() :: [String.t()]
  def list_encoding_names do
    @encoding_specs |> Map.keys() |> Enum.sort()
  end
end
