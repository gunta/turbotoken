defmodule TurboToken.Chat do
  @moduledoc """
  Chat message encoding support for TurboToken.

  Supports OpenAI-style chat message formatting with configurable templates.
  """

  alias TurboToken.Encoding

  @type chat_message :: %{role: String.t(), content: String.t()} | %{String.t() => String.t()}
  @type template_mode :: :turbotoken_v1 | :im_tokens

  @type chat_template :: %{
          tokens_per_message: non_neg_integer(),
          tokens_per_name: non_neg_integer(),
          bos_token_ids: [non_neg_integer()],
          eos_token_ids: [non_neg_integer()]
        }

  @doc """
  Resolve a chat template by mode.
  """
  @spec resolve_chat_template(template_mode(), map()) :: chat_template()
  def resolve_chat_template(:turbotoken_v1, spec) do
    eot = spec.special_tokens["<|endoftext|>"] || 0

    %{
      tokens_per_message: 3,
      tokens_per_name: 1,
      bos_token_ids: [],
      eos_token_ids: [eot]
    }
  end

  def resolve_chat_template(:im_tokens, spec) do
    eot = spec.special_tokens["<|endoftext|>"] || 0

    %{
      tokens_per_message: 4,
      tokens_per_name: -1,
      bos_token_ids: [],
      eos_token_ids: [eot]
    }
  end

  @doc """
  Encode chat messages into token IDs.
  """
  @spec encode_chat(Encoding.t(), [chat_message()], keyword()) ::
          {:ok, [non_neg_integer()]} | {:error, term()}
  def encode_chat(%Encoding{} = enc, messages, opts \\ []) do
    mode = Keyword.get(opts, :mode, :turbotoken_v1)
    template = resolve_chat_template(mode, enc.spec)

    results =
      Enum.reduce_while(messages, {:ok, []}, fn msg, {:ok, acc} ->
        role = msg[:role] || msg["role"] || ""
        content = msg[:content] || msg["content"] || ""
        name = msg[:name] || msg["name"]

        with {:ok, role_tokens} <- Encoding.encode(enc, role),
             {:ok, content_tokens} <- Encoding.encode(enc, content) do
          msg_tokens =
            template.bos_token_ids ++
              role_tokens ++
              content_tokens ++
              if(name, do: name_tokens(enc, name, template), else: []) ++
              List.duplicate(0, template.tokens_per_message)

          {:cont, {:ok, acc ++ msg_tokens}}
        else
          err -> {:halt, err}
        end
      end)

    case results do
      {:ok, tokens} -> {:ok, tokens ++ template.eos_token_ids}
      err -> err
    end
  end

  @doc """
  Count tokens in chat messages.
  """
  @spec count_chat(Encoding.t(), [chat_message()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def count_chat(%Encoding{} = enc, messages, opts \\ []) do
    case encode_chat(enc, messages, opts) do
      {:ok, tokens} -> {:ok, length(tokens)}
      err -> err
    end
  end

  defp name_tokens(enc, name, template) do
    case Encoding.encode(enc, name) do
      {:ok, tokens} -> tokens ++ List.duplicate(0, template.tokens_per_name)
      _ -> []
    end
  end
end
