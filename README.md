# FALCON

A self-hosted LLM web interface built with Elixir/Phoenix, inspired by [Open WebUI](https://github.com/open-webui/open-webui). Designed for local/Tailscale use with first-class support for folder-scoped agent chats.

## Why FALCON?

Open WebUI is powerful but Python-heavy. Phoenix LiveView gives us real-time streaming over WebSockets natively, OTP provides robust per-thread concurrency via GenServers, and PubSub makes multi-session updates trivial. FALCON takes the best ideas from Open WebUI and builds them on a stack purpose-built for real-time, concurrent workloads.

## Features

### Core
- **Universal LLM support** -- Ollama, OpenAI-compatible APIs, Hugging Face Inference/TGI, Anthropic
- **Chat threads with per-thread model selection** -- pick your model when starting a conversation
- **Streaming responses** -- LiveView WebSocket streaming, no SSE/polling hacks
- **File attachments** -- drag/drop or paste images and PDFs for multimodal models
- **Folder-scoped agent chats** -- assign a directory to a chat thread, giving the LLM sandboxed file/command access within that path
- **Email/password auth** -- simple, local-first authentication
- **Conversation history** -- persistent, searchable threads

### Feature Priority

| Feature | Priority | Status | Notes |
|---|---|---|---|
| Email/password auth | High | Done | phx.gen.auth LiveView |
| Chat threads + streaming | High | Building | Per-thread GenServer orchestration |
| Universal LLM providers | High | Building | Behaviour-based provider abstraction |
| Folder-scoped agent tools | High | Building | PathSandbox + read/write/list/exec |
| File attachments (images, PDFs) | High | Planned | Multimodal support |
| Model parameter tuning per chat | High | Planned | temperature, top_p, context length, etc. |
| Conversation branching | High | Planned | Fork at any message, explore alternatives |
| System prompt / persona presets | High | Planned | Reusable agent configurations |
| Multi-model chat | Medium | Planned | Send same prompt to N models for comparison |
| RAG / knowledge bases | Medium | Planned | Document embeddings + vector search |
| Code execution sandbox | Medium | Planned | Sandboxed command execution in agent mode |
| Web search integration | Medium | Planned | For non-code research chats |
| HF Endpoint cost guard | Medium | Planned | Auto-pause/shutdown via HF API, runtime alerts |
| Export chats (JSON/PDF) | Low | Planned | |
| Voice/TTS/STT | Low | Planned | |
| Model arena / A/B testing | Low | Planned | Blind comparison with Elo ratings |

## Architecture

- **Phoenix 1.8 + LiveView** -- real-time UI with no JavaScript framework
- **PostgreSQL** -- persistent storage for users, threads, messages, model configs
- **OTP GenServers** -- one per active chat thread, managing LLM interaction lifecycle
- **Behaviour-based LLM providers** -- pluggable adapters for any backend
- **PathSandbox** -- per-thread directory restrictions for agent tool access
- **PubSub** -- broadcast streaming tokens and status updates to connected clients

## Getting Started (Dev)

```bash
# Install dependencies, create DB, run migrations + seeds, build assets
mix setup

# Start the server
mix phx.server
```

Then visit [`localhost:4000`](http://localhost:4000). The first user to register becomes admin.

## Local Deploy (Prod)

Runs via Docker on port 5000 behind Caddy reverse proxy on Tailscale.

### Prerequisites

- Docker + Docker Compose
- PostgreSQL accessible from the Docker container
- Caddy (or another reverse proxy) routing to port 5000

### Setup

1. Copy the example env and fill in your values:

   ```bash
   cp .env.example .env
   ```

   | Variable | Default | Description |
   |---|---|---|
   | `DATABASE_URL` | -- | PostgreSQL connection string (e.g. `ecto://postgres:postgres@host.docker.internal/falcon_prod`) |
   | `SECRET_KEY_BASE` | -- | Generate with `mix phx.gen.secret` |
   | `PHX_HOST` | `localhost` | Hostname or IP (e.g. Tailscale IP) |
   | `PORT` | `4000` | HTTP port (use `5000` for prod) |
   | `OLLAMA_URL` | `http://host.docker.internal:11434` | Ollama API endpoint |

2. Build and start:

   ```bash
   docker compose up -d --build
   ```

   On first boot this will automatically create the database and run all migrations. On subsequent restarts it runs any pending migrations before starting the server.

3. View logs:

   ```bash
   docker compose logs -f falcon
   ```

### Useful Commands

```bash
# Rebuild after code changes
docker compose up -d --build

# Stop
docker compose down

# Remote console into running container
docker exec -it falcon bin/falcon remote

# Run migrations manually
docker exec -it falcon bin/migrate
```

### Configuration

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | (dev config) | PostgreSQL connection string |
| `OLLAMA_URL` | `http://localhost:11434` | Ollama API endpoint |
| `PORT` | `4000` | HTTP port |
| `SECRET_KEY_BASE` | (dev config) | Cookie signing key (prod) |

## Documentation

See `docs/` for detailed documentation:

- [`docs/architecture.md`](docs/architecture.md) -- System architecture and design decisions
- [`docs/llm-providers.md`](docs/llm-providers.md) -- LLM provider abstraction and adding new providers
- [`docs/agent-tools.md`](docs/agent-tools.md) -- Folder-scoped agent tools and PathSandbox
- [`docs/chat-system.md`](docs/chat-system.md) -- Chat threading, streaming, and message handling
- [`docs/design.md`](docs/design.md) -- Design system, color palette, logo, CSS classes, and UI components

### Provider Setup Guides

- [`docs/setup-ollama.md`](docs/setup-ollama.md) -- Local models with Ollama
- [`docs/setup-huggingface.md`](docs/setup-huggingface.md) -- Hugging Face (serverless API, TGI self-hosted, Inference Endpoints)
- [`docs/setup-openai.md`](docs/setup-openai.md) -- OpenAI (GPT-4o, etc.)
- [`docs/setup-openai-compatible.md`](docs/setup-openai-compatible.md) -- LM Studio, Groq, OpenRouter, vLLM, Anthropic via proxy

## License

Private -- not yet licensed for distribution.
