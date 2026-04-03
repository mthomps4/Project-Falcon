# Architecture

## Overview

FALCON is a Phoenix 1.8 LiveView application with PostgreSQL storage and OTP-based concurrency for managing LLM interactions.

## System Diagram

```
┌─ Browser (LiveView WebSocket)
│
├─ FalconWeb.Endpoint
│  ├─ UserAuth (session/cookie auth)
│  └─ Router
│     ├─ ChatLive (main UI — sidebar, messages, streaming)
│     ├─ Auth controllers (register, login, settings)
│     └─ LiveDashboard (dev)
│
├─ Application Supervision Tree
│  ├─ Falcon.Repo (Ecto/PostgreSQL)
│  ├─ Phoenix.PubSub (Falcon.PubSub)
│  ├─ Registry (Falcon.ThreadRegistry — unique, keyed by thread_id)
│  ├─ DynamicSupervisor (Falcon.ThreadSupervisor)
│  │   └─ Falcon.Chat.ThreadServer (one per active thread)
│  └─ FalconWeb.Endpoint
│
├─ Contexts
│  ├─ Falcon.Accounts — User auth (phx.gen.auth)
│  ├─ Falcon.Chat — Thread/message CRUD, PubSub broadcasts
│  ├─ Falcon.Providers — LLM provider configuration
│  └─ Falcon.LLM.ProviderRegistry — maps provider types to modules
│
├─ LLM Providers (Behaviour: Falcon.LLM)
│  ├─ Falcon.LLM.Ollama — local/remote Ollama
│  └─ Falcon.LLM.OpenAI — OpenAI-compatible APIs (OpenAI, HF, vLLM, etc.)
│
└─ Agent Tools (Falcon.Chat.Tools)
   ├─ PathSandbox — directory restriction enforcement
   ├─ read_file — read within allowed paths
   ├─ write_file — write within allowed paths
   ├─ list_directory — browse within allowed paths
   └─ run_command — execute shell commands (30s timeout)
```

## Key Design Decisions

### One GenServer per Thread

Each active chat thread gets its own `Falcon.Chat.ThreadServer` GenServer, started on-demand and supervised by a `DynamicSupervisor`. This provides:

- **Isolation**: a crash in one thread doesn't affect others
- **Backpressure**: each thread manages its own LLM streaming task
- **State management**: streaming buffer, tool call rounds, and thread metadata are held in process state
- **Auto-cleanup**: idle threads stop after 30 minutes

### Behaviour-Based LLM Providers

`Falcon.LLM` defines a behaviour with three callbacks:
- `list_models/0` — enumerate available models
- `stream_chat/3` — start streaming chat with messages sent to a pid
- `supports?/2` — capability detection (vision, tool_calling)

New providers implement this behaviour. Provider instances are stored in the `providers` table with type, URL, and API key.

### Streaming via PubSub

The ThreadServer streams LLM tokens by sending messages to itself, then broadcasts via PubSub to `"thread:{id}"`. The LiveView subscribes to this topic and pushes chunks to the client in real-time.

```
LLM API → Task → {:llm_chunk, content} → ThreadServer → PubSub → ChatLive → Browser
```

### Path Sandbox

Agent tools are gated by `scoped_paths` on the thread. When paths are empty, no tools are available. The `PathSandbox` module validates and resolves paths against the allowed list, preventing directory traversal.

## Database Schema

```
users (phx.gen.auth)
├── providers (LLM backend configs)
├── threads (chat conversations)
│   ├── model, system_prompt, parameters
│   ├── scoped_paths, allowed_tools (agent mode)
│   └── messages (user/assistant/tool/system)
│       └── attachments (files uploaded to messages)
```

All tables use `binary_id` (UUID) primary keys.
