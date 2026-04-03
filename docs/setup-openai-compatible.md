# Setup: OpenAI-Compatible Providers

FALCON's OpenAI provider works with any API that follows the OpenAI chat completions spec. This covers a huge range of services and local servers.

## LM Studio

Run models locally with a GUI. Exposes an OpenAI-compatible server.

1. Download from [lmstudio.ai](https://lmstudio.ai)
2. Download a model from the built-in browser (GGUF format)
3. Go to the Server tab and start the server (default: `http://localhost:1234`)

```elixir
Falcon.Providers.create_provider(%{
  name: "LM Studio",
  type: "openai",
  base_url: "http://localhost:1234"
  # No API key needed for local
})
```

## Groq

Extremely fast inference on custom LPU hardware. Free tier available.

1. Sign up at [console.groq.com](https://console.groq.com)
2. Create an API key
3. Models: `llama-3.1-70b-versatile`, `llama-3.1-8b-instant`, `mixtral-8x7b-32768`, `gemma2-9b-it`

```elixir
Falcon.Providers.create_provider(%{
  name: "Groq",
  type: "openai",
  base_url: "https://api.groq.com/openai",
  api_key: "gsk_..."
})
```

**Free tier limits**: 30 requests/min for most models. Fast enough for personal use.

## OpenRouter

Aggregator — access 100+ models through one API. Pay-per-token across providers.

1. Sign up at [openrouter.ai](https://openrouter.ai)
2. Create an API key
3. Browse models at [openrouter.ai/models](https://openrouter.ai/models)

```elixir
Falcon.Providers.create_provider(%{
  name: "OpenRouter",
  type: "openai",
  base_url: "https://openrouter.ai/api",
  api_key: "sk-or-..."
})
```

Model IDs use the format `provider/model-name`, e.g., `meta-llama/llama-3.1-70b-instruct`.

## vLLM

High-throughput local inference server. Good for larger models on multi-GPU setups.

```bash
# Install
pip install vllm

# Serve a model
python -m vllm.entrypoints.openai.api_server \
  --model meta-llama/Meta-Llama-3.1-8B-Instruct \
  --port 8000
```

```elixir
Falcon.Providers.create_provider(%{
  name: "vLLM Local",
  type: "openai",
  base_url: "http://localhost:8000"
})
```

## Anthropic (via Proxy)

Anthropic's API is not directly OpenAI-compatible, but you can use a proxy like [LiteLLM](https://github.com/BerriAI/litellm) to expose Claude models as an OpenAI-compatible endpoint:

```bash
pip install litellm
litellm --model claude-sonnet-4-20250514 --port 4001
```

```elixir
Falcon.Providers.create_provider(%{
  name: "Claude (via LiteLLM)",
  type: "openai",
  base_url: "http://localhost:4001",
  api_key: "sk-..."  # Your Anthropic key
})
```

## Any Other OpenAI-Compatible Server

The pattern is always the same:

```elixir
Falcon.Providers.create_provider(%{
  name: "My Provider",
  type: "openai",
  base_url: "http://host:port",  # Must serve /v1/chat/completions
  api_key: "optional-key"
})
```

FALCON calls:
- `GET {base_url}/v1/models` — to list available models
- `POST {base_url}/v1/chat/completions` — for streaming chat

As long as your server implements these two endpoints, it works with FALCON.
