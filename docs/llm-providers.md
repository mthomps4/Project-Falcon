# LLM Providers

## Overview

FALCON uses a behaviour-based provider system. Each provider implements the `Falcon.LLM` behaviour, which defines three callbacks for model listing, streaming chat, and capability detection.

## Supported Providers

### Ollama (`Falcon.LLM.Ollama`)

Local or remote Ollama instance. Default provider, auto-created on first boot.

**Configuration:**
- `OLLAMA_URL` environment variable (default: `http://localhost:11434`)
- Or create a provider record with type `"ollama"` and custom `base_url`

**Features:**
- Model listing via `/api/tags`
- Streaming chat via `/api/chat`
- Tool calling support
- Vision/image support (base64 encoded)

### OpenAI-Compatible (`Falcon.LLM.OpenAI`)

Works with any OpenAI-compatible API:
- **OpenAI** — `https://api.openai.com`
- **Hugging Face TGI** — `http://localhost:8080` (or remote)
- **vLLM** — `http://localhost:8000`
- **LM Studio** — `http://localhost:1234`
- **Groq** — `https://api.groq.com/openai`
- **OpenRouter** — `https://openrouter.ai/api`

**Configuration:**
Create a provider record:
```elixir
Falcon.Providers.create_provider(%{
  name: "Hugging Face",
  type: "openai",
  base_url: "http://localhost:8080",
  api_key: nil  # or your API key
})
```

**Features:**
- Model listing via `/v1/models`
- Streaming chat via `/v1/chat/completions` (SSE)
- Tool calling via function calling protocol
- Vision via content array with `image_url` type

## Adding a New Provider

1. Create a module implementing `Falcon.LLM`:

```elixir
defmodule Falcon.LLM.MyProvider do
  @behaviour Falcon.LLM

  @impl true
  def list_models do
    # Return {:ok, [%{id: "model-id", name: "Display Name", provider: :my_provider}]}
  end

  @impl true
  def stream_chat(messages, model, opts) do
    stream_to = Keyword.fetch!(opts, :stream_to)
    # Start async task that sends:
    #   {:llm_chunk, content} — text tokens
    #   {:llm_tool_calls, calls} — tool call requests
    #   :llm_done — completion
    #   {:llm_error, reason} — failure
    # Return {:ok, task}
  end

  @impl true
  def supports?(_model, _capability), do: false
end
```

2. Register it in `Falcon.LLM.ProviderRegistry`:

```elixir
@provider_modules %{
  "ollama" => Falcon.LLM.Ollama,
  "openai" => Falcon.LLM.OpenAI,
  "my_provider" => Falcon.LLM.MyProvider
}
```

3. Add `"my_provider"` to the `validate_inclusion` in `Falcon.Providers.Provider.changeset/2`.

## Streaming Protocol

All providers communicate with the `ThreadServer` via process messages:

| Message | Description |
|---|---|
| `{:llm_chunk, binary}` | Partial text token from the model |
| `{:llm_tool_calls, [map]}` | Model requests tool execution |
| `:llm_done` | Generation complete |
| `{:llm_error, binary}` | Error occurred |

The `ThreadServer` accumulates chunks into a buffer, broadcasts them via PubSub, and persists the complete message when `:llm_done` is received.

## Model Parameters

Per-thread model parameters are stored in the `parameters` map field:

| Parameter | Type | Description |
|---|---|---|
| `temperature` | float | Randomness (0.0-2.0) |
| `top_p` | float | Nucleus sampling (0.0-1.0) |
| `top_k` | integer | Top-K sampling |
| `max_tokens` | integer | Max response tokens |

Parameters are passed through to the provider's API. Ollama maps `max_tokens` to `num_predict`.
