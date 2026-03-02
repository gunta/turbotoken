defmodule TurboToken.Encoding do
  @moduledoc """
  An initialized BPE encoding with loaded rank data.
  """

  alias TurboToken.{Nif, Chat, Registry}

  @type t :: %__MODULE__{
          name: String.t(),
          spec: Registry.encoding_spec(),
          rank_payload: binary()
        }

  defstruct [:name, :spec, :rank_payload]

  @doc """
  Encode text into a list of BPE token IDs.
  """
  @spec encode(t(), String.t()) :: {:ok, [non_neg_integer()]} | {:error, term()}
  def encode(%__MODULE__{rank_payload: rp}, text) when is_binary(text) do
    Nif.encode_bpe(rp, text)
  end

  @doc """
  Decode a list of BPE token IDs back to a UTF-8 binary.
  """
  @spec decode(t(), [non_neg_integer()]) :: {:ok, binary()} | {:error, term()}
  def decode(%__MODULE__{rank_payload: rp}, tokens) when is_list(tokens) do
    Nif.decode_bpe(rp, tokens)
  end

  @doc """
  Count the number of BPE tokens in text without materializing the token list.
  """
  @spec count(t(), String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(%__MODULE__{rank_payload: rp}, text) when is_binary(text) do
    Nif.count_bpe(rp, text)
  end

  @doc """
  Alias for `count/2`.
  """
  @spec count_tokens(t(), String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_tokens(enc, text), do: count(enc, text)

  @doc """
  Check if text is within a token limit.
  Returns `{:ok, count}` if within limit, `{:ok, false}` if exceeded.
  """
  @spec is_within_token_limit(t(), String.t(), non_neg_integer()) ::
          {:ok, non_neg_integer() | false} | {:error, term()}
  def is_within_token_limit(%__MODULE__{rank_payload: rp}, text, limit)
      when is_binary(text) and is_integer(limit) and limit >= 0 do
    Nif.is_within_token_limit(rp, text, limit)
  end

  @doc """
  Encode a list of chat messages into token IDs.
  """
  @spec encode_chat(t(), [Chat.chat_message()], keyword()) ::
          {:ok, [non_neg_integer()]} | {:error, term()}
  def encode_chat(%__MODULE__{} = enc, messages, opts \\ []) do
    Chat.encode_chat(enc, messages, opts)
  end

  @doc """
  Count tokens in a list of chat messages.
  """
  @spec count_chat(t(), [Chat.chat_message()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def count_chat(%__MODULE__{} = enc, messages, opts \\ []) do
    Chat.count_chat(enc, messages, opts)
  end

  @doc """
  Check if chat messages are within a token limit.
  """
  @spec is_chat_within_token_limit(t(), [Chat.chat_message()], non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer() | false} | {:error, term()}
  def is_chat_within_token_limit(%__MODULE__{} = enc, messages, limit, opts \\ []) do
    case count_chat(enc, messages, opts) do
      {:ok, count} -> {:ok, if(count <= limit, do: count, else: false)}
      err -> err
    end
  end

  @doc """
  Encode a file's contents into token IDs.
  """
  @spec encode_file_path(t(), String.t()) :: {:ok, [non_neg_integer()]} | {:error, term()}
  def encode_file_path(%__MODULE__{} = enc, path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} -> encode(enc, content)
      {:error, reason} -> {:error, {:file_read, reason}}
    end
  end

  @doc """
  Count tokens in a file using the native file counting path.
  """
  @spec count_file_path(t(), String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_file_path(%__MODULE__{rank_payload: rp}, path) when is_binary(path) do
    Nif.count_bpe_file(rp, path)
  end
end
