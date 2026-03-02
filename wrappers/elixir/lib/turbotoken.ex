defmodule TurboToken do
  @moduledoc """
  TurboToken - the fastest BPE tokenizer on every platform.

  Drop-in replacement for tiktoken with identical output.
  """

  alias TurboToken.{Encoding, Registry, RankCache}

  @doc """
  Get an encoding by name (e.g. "cl100k_base", "o200k_base").
  """
  @spec get_encoding(String.t()) :: {:ok, Encoding.t()} | {:error, term()}
  def get_encoding(name) when is_binary(name) do
    with {:ok, spec} <- Registry.get_encoding_spec(name),
         {:ok, rank_payload} <- RankCache.ensure_rank_file(name) do
      {:ok, %Encoding{name: name, spec: spec, rank_payload: rank_payload}}
    end
  end

  @doc """
  Get the encoding for a given model name (e.g. "gpt-4o", "gpt-3.5-turbo").
  """
  @spec get_encoding_for_model(String.t()) :: {:ok, Encoding.t()} | {:error, term()}
  def get_encoding_for_model(model) when is_binary(model) do
    case Registry.model_to_encoding(model) do
      {:ok, encoding_name} -> get_encoding(encoding_name)
      {:error, _} = err -> err
    end
  end

  @doc """
  List all supported encoding names.
  """
  @spec list_encoding_names() :: [String.t()]
  def list_encoding_names do
    Registry.list_encoding_names()
  end

  @doc """
  Return the turbotoken native library version string.
  """
  @spec version() :: String.t()
  def version do
    TurboToken.Nif.version() |> to_string()
  end
end
