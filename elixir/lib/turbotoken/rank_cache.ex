defmodule TurboToken.RankCache do
  @moduledoc """
  Downloads and caches BPE rank files from OpenAI's public blob storage.
  """

  alias TurboToken.Registry

  @cache_subdir "turbotoken"

  @doc """
  Returns the cache directory path, creating it if needed.
  """
  @spec cache_dir() :: String.t()
  def cache_dir do
    base =
      System.get_env("TURBOTOKEN_CACHE_DIR") ||
        Path.join(System.get_env("XDG_CACHE_HOME", Path.expand("~/.cache")), @cache_subdir)

    File.mkdir_p!(base)
    base
  end

  @doc """
  Ensure the rank file for the given encoding is downloaded and cached.
  Returns `{:ok, binary}` with the raw rank file bytes.
  """
  @spec ensure_rank_file(String.t()) :: {:ok, binary()} | {:error, term()}
  def ensure_rank_file(name) do
    case Registry.get_encoding_spec(name) do
      {:ok, spec} ->
        path = Path.join(cache_dir(), "#{name}.tiktoken")

        if File.exists?(path) do
          read_rank_file(path)
        else
          download_rank_file(spec.rank_file_url, path)
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Read a cached rank file from disk.
  """
  @spec read_rank_file(String.t()) :: {:ok, binary()} | {:error, term()}
  def read_rank_file(path) do
    case File.read(path) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:rank_read_failed, reason}}
    end
  end

  defp download_rank_file(url, dest_path) do
    :ok = ensure_http_started()

    url_charlist = String.to_charlist(url)

    ssl_opts = [
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 3,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    case :httpc.request(:get, {url_charlist, []}, ssl_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        File.write!(dest_path, body)
        {:ok, body}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:download_failed, status, url}}

      {:error, reason} ->
        {:error, {:download_failed, reason}}
    end
  end

  defp ensure_http_started do
    case :inets.start() do
      :ok -> :ok
      {:error, {:already_started, :inets}} -> :ok
    end

    case :ssl.start() do
      :ok -> :ok
      {:error, {:already_started, :ssl}} -> :ok
    end

    :ok
  end
end
