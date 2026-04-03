# Setup: Ollama

Ollama runs LLMs locally on your machine. FALCON auto-creates a "Local Ollama" provider on first boot.

## Install Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Or on Arch:

```bash
pacman -S ollama
```

## Start the Server

```bash
ollama serve
```

Default: `http://localhost:11434`. To listen on all interfaces (for Tailscale access from other machines):

```bash
OLLAMA_HOST=0.0.0.0 ollama serve
```

## Pull Models

```bash
# General purpose
ollama pull llama3.1:8b
ollama pull llama3.1:70b

# Code-focused
ollama pull deepseek-coder-v2:16b
ollama pull qwen2.5-coder:7b

# Small/fast
ollama pull qwen3:8b
ollama pull phi3:mini

# Vision (image support)
ollama pull llava:7b
ollama pull llama3.2-vision:11b
```

List what you have:

```bash
ollama list
```

## Configure in FALCON

FALCON creates the Ollama provider automatically using the `OLLAMA_URL` environment variable (defaults to `http://localhost:11434`).

To point at a remote Ollama instance (e.g., a GPU server on your Tailscale network):

```bash
OLLAMA_URL=http://gpu-server:11434 mix phx.server
```

Or set it in `config/runtime.exs`:

```elixir
config :falcon, :ollama_url, "http://gpu-server:11434"
```

You can also create additional Ollama provider entries in the database if you run multiple Ollama instances:

```elixir
Falcon.Providers.create_provider(%{
  name: "GPU Server",
  type: "ollama",
  base_url: "http://gpu-server:11434"
})
```

## Model Selection

When creating a new chat thread in FALCON, the model dropdown lists all models from your Ollama instance. Pick whichever you've pulled.

## Recommended Models

| Model | Size | Best For |
|---|---|---|
| `llama3.1:8b` | 4.7 GB | General chat, good all-rounder |
| `llama3.1:70b` | 40 GB | High quality, needs serious GPU |
| `qwen3:8b` | 4.9 GB | Fast, good reasoning |
| `deepseek-coder-v2:16b` | 8.9 GB | Code generation and review |
| `qwen2.5-coder:7b` | 4.4 GB | Code, fits in less VRAM |
| `llava:7b` | 4.5 GB | Vision — can analyze images |
| `phi3:mini` | 2.2 GB | Lightweight, fast responses |

## Agent Mode

All Ollama models support FALCON's agent tools (read/write files, run commands) via Ollama's native tool calling. When you set scoped paths on a thread, tool definitions are sent with each request.

## Troubleshooting

**"Connection refused"**: Make sure `ollama serve` is running.

**Models not showing up**: Check `ollama list`. If empty, pull a model first.

**Slow responses**: Ollama loads models into memory on first use. Subsequent requests are faster. If you're running out of VRAM, try a smaller model or set `OLLAMA_NUM_GPU=0` for CPU-only mode.

**Remote access**: By default Ollama binds to localhost. Set `OLLAMA_HOST=0.0.0.0` to allow connections from other machines on your Tailscale network.
