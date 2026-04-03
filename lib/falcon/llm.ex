defmodule Falcon.LLM do
  @moduledoc """
  Behaviour for LLM providers. Each provider implements streaming chat,
  model listing, and capability detection.
  """

  @type message :: %{role: String.t(), content: String.t(), images: [String.t()]}
  @type model :: %{id: String.t(), name: String.t(), provider: atom()}
  @type stream_opt ::
          {:temperature, float()}
          | {:top_p, float()}
          | {:top_k, integer()}
          | {:max_tokens, integer()}
          | {:system, String.t()}
          | {:tools, [map()]}
          | {:stream_to, pid()}

  @type provider_config :: %{base_url: String.t(), api_key: String.t() | nil}

  @doc "List available models from this provider."
  @callback list_models(config :: provider_config()) :: {:ok, [model()]} | {:error, term()}

  @doc """
  Start a streaming chat completion. Sends messages to `stream_to` pid:
  - `{:llm_chunk, content}` — partial text token
  - `{:llm_tool_calls, [tool_call]}` — model requests tool execution
  - `:llm_done` — generation complete
  - `{:llm_error, reason}` — failure
  """
  @callback stream_chat(config :: provider_config(), messages :: [message()], model :: String.t(), opts :: [stream_opt()]) ::
              {:ok, Task.t()} | {:error, term()}

  @doc "Check if a model supports a capability (e.g., :vision, :tool_calling)."
  @callback supports?(model :: String.t(), capability :: atom()) :: boolean()
end
