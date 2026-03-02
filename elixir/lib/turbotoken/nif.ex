defmodule TurboToken.Nif do
  @moduledoc """
  NIF bindings to the turbotoken native library.
  """

  @on_load :load_nif

  @doc false
  def load_nif do
    nif_path =
      :turbotoken
      |> :code.priv_dir()
      |> Path.join("turbotoken_nif")
      |> String.to_charlist()

    :erlang.load_nif(nif_path, 0)
  end

  @doc "Return native library version string."
  @spec version() :: charlist()
  def version, do: :erlang.nif_error(:not_loaded)

  @doc "Clear the internal rank table cache."
  @spec clear_rank_table_cache() :: :ok
  def clear_rank_table_cache, do: :erlang.nif_error(:not_loaded)

  @doc "BPE-encode text using rank payload. Returns {:ok, [integer()]} or {:error, atom()}."
  @spec encode_bpe(binary(), binary()) :: {:ok, [non_neg_integer()]} | {:error, atom()}
  def encode_bpe(_rank_payload, _text), do: :erlang.nif_error(:not_loaded)

  @doc "BPE-decode token IDs using rank payload. Returns {:ok, binary()} or {:error, atom()}."
  @spec decode_bpe(binary(), [non_neg_integer()]) :: {:ok, binary()} | {:error, atom()}
  def decode_bpe(_rank_payload, _tokens), do: :erlang.nif_error(:not_loaded)

  @doc "Count BPE tokens without materializing. Returns {:ok, integer()} or {:error, atom()}."
  @spec count_bpe(binary(), binary()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def count_bpe(_rank_payload, _text), do: :erlang.nif_error(:not_loaded)

  @doc "Check if text is within token limit."
  @spec is_within_token_limit(binary(), binary(), non_neg_integer()) ::
          {:ok, non_neg_integer() | false} | {:error, atom()}
  def is_within_token_limit(_rank_payload, _text, _limit), do: :erlang.nif_error(:not_loaded)

  @doc "Count BPE tokens in a file."
  @spec count_bpe_file(binary(), binary()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def count_bpe_file(_rank_payload, _file_path), do: :erlang.nif_error(:not_loaded)

  @doc "Train BPE merges from chunk counts."
  @spec train_bpe(binary(), [non_neg_integer()], [non_neg_integer()], non_neg_integer(), non_neg_integer()) ::
          {:ok, [non_neg_integer()]} | {:error, atom()}
  def train_bpe(_chunks, _offsets, _counts, _vocab_size, _min_freq),
    do: :erlang.nif_error(:not_loaded)
end
