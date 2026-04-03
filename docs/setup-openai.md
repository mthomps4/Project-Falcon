# Setup: OpenAI

Connect FALCON to OpenAI's API for access to GPT-4o, GPT-4, GPT-3.5, and other OpenAI models.

## Get an API Key

1. Go to [platform.openai.com](https://platform.openai.com)
2. Navigate to API Keys
3. Create a new secret key
4. Copy it — you'll need it for the provider config

## Configure in FALCON

Create a provider via IEx or seeds:

```elixir
Falcon.Providers.create_provider(%{
  name: "OpenAI",
  type: "openai",
  base_url: "https://api.openai.com",
  api_key: "sk-..."
})
```

Or set via environment/config for a single global instance:

```elixir
# config/runtime.exs
config :falcon, :openai_base_url, "https://api.openai.com"
config :falcon, :openai_api_key, System.get_env("OPENAI_API_KEY")
```

## Available Models

Once configured, FALCON will list all models from the `/v1/models` endpoint. Key ones:

| Model | Notes |
|---|---|
| `gpt-4o` | Best overall — fast, multimodal (images) |
| `gpt-4o-mini` | Cheaper, still capable |
| `gpt-4-turbo` | Strong reasoning |
| `gpt-3.5-turbo` | Fast, cheap, good for simple tasks |
| `o1` | Advanced reasoning, slower |

## Features

- **Streaming**: Full SSE streaming support
- **Vision**: GPT-4o and GPT-4-turbo can analyze images — paste or drag images into chat
- **Tool calling**: Native function calling support for FALCON's agent tools
- **Model parameters**: Temperature, top_p, max_tokens all supported

## Cost Notes

OpenAI charges per token. Monitor your usage at [platform.openai.com/usage](https://platform.openai.com/usage). For local/free alternatives, use Ollama instead.
