# Chat System

## Overview

The chat system is organized around **threads** (conversations) containing **messages**. Each thread is bound to a specific LLM model and optionally scoped to directories for agent mode.

## Data Model

### Thread

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Primary key |
| `title` | string | Auto-generated from first user message |
| `model` | string | LLM model identifier (e.g., `llama3.1:8b`) |
| `system_prompt` | text | Optional system instructions |
| `status` | string | `idle`, `active`, `error` |
| `scoped_paths` | string[] | Directories for agent tool access |
| `allowed_tools` | string[] | Tool whitelist (empty = all) |
| `parameters` | map | Model params (temperature, top_p, etc.) |
| `provider_id` | UUID | Which LLM provider to use |
| `user_id` | UUID | Owner |

### Message

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Primary key |
| `role` | string | `user`, `assistant`, `system`, `tool` |
| `content` | text | Message content |
| `parent_id` | UUID | For conversation branching (future) |
| `metadata` | map | Tool calls, model info, etc. |
| `thread_id` | UUID | Parent thread |

### Attachment

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Primary key |
| `filename` | string | Original filename |
| `content_type` | string | MIME type |
| `size` | integer | Bytes |
| `storage_path` | string | On-disk location |
| `message_id` | UUID | Parent message |

## ThreadServer Lifecycle

```
User sends message
  │
  ├─ ChatLive calls ThreadServer.send_message(thread_id, content)
  │    │
  │    ├─ ensure_started() — starts GenServer if not running
  │    │    └─ DynamicSupervisor.start_child(ThreadSupervisor, {ThreadServer, thread_id})
  │    │
  │    └─ GenServer.call({:send_message, content, opts})
  │         │
  │         ├─ Create user message in DB
  │         ├─ Build message history (Chat.messages_for_llm)
  │         ├─ Prepend system prompt if configured
  │         ├─ Resolve LLM provider
  │         ├─ Start streaming task (provider.stream_chat)
  │         │
  │         └─ Streaming loop:
  │              ├─ {:llm_chunk, content} → buffer + PubSub broadcast
  │              ├─ {:llm_tool_calls, calls} → execute tools, loop back
  │              ├─ :llm_done → save assistant message, broadcast :stream_done
  │              └─ {:llm_error, reason} → broadcast error
  │
  └─ Idle timeout (30 min) → GenServer stops
```

## PubSub Topics

| Topic | Messages | Subscribers |
|---|---|---|
| `thread:{id}` | `{:stream_chunk, content}` | ChatLive |
| | `:stream_done` | |
| | `{:stream_error, reason}` | |
| | `{:new_message, message}` | |
| | `{:thread_status, status}` | |

## LiveView Integration

`ChatLive` subscribes to the current thread's PubSub topic. Streaming chunks are accumulated in an `@stream_buffer` assign and rendered in real-time. When streaming completes, the buffer is cleared and messages are reloaded from the database.

### Key Events

| Event | Trigger | Action |
|---|---|---|
| `new_thread` | Click "New Chat" | Show modal |
| `create_thread` | Submit modal form | Create thread, navigate to it |
| `send_message` | Submit message form | Call ThreadServer, start streaming |
| `select_thread` | Click sidebar thread | Navigate to thread |
| `archive_thread` | Click archive icon | Soft-delete thread |

### JavaScript Hooks

- `ScrollBottom` — auto-scrolls message container on new content
- `MessageInput` — handles Enter-to-submit and input clearing after send

## Auto-Titling

Threads start without a title. After the first assistant response, the thread is titled with the first 60 characters of the user's initial message.

## Conversation Branching (Planned)

The `parent_id` field on messages supports future conversation branching. When implemented, users will be able to fork a conversation at any message to explore alternatives.
