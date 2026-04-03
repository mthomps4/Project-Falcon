# Agent Tools

## Overview

FALCON provides folder-scoped agent capabilities. When a chat thread has `scoped_paths` configured, the LLM gains access to file system and command execution tools within those directories.

## How It Works

1. **Thread creation**: User specifies one or more directory paths when creating a chat
2. **Tool injection**: When the thread has scoped paths, tool definitions are sent to the LLM alongside messages
3. **Tool calling**: The LLM can request tool execution via its native function calling protocol
4. **Path validation**: Every file path argument is validated against the sandbox before execution
5. **Result loop**: Tool results are added as messages and the LLM continues reasoning

## Available Tools

### `read_file`

Read the contents of a file within allowed paths.

**Parameters:**
- `path` (string, required) — path to the file

**Sandbox behavior:** Relative paths resolve against the first allowed directory. Absolute paths must fall within an allowed directory.

### `write_file`

Write content to a file. Creates parent directories if needed.

**Parameters:**
- `path` (string, required) — path to the file
- `content` (string, required) — content to write

### `list_directory`

List files and directories, with type indicators.

**Parameters:**
- `path` (string, required) — directory path

**Output format:**
```
dir     src
dir     test
file    mix.exs
file    README.md
```

### `run_command`

Execute a shell command within an allowed directory.

**Parameters:**
- `command` (string, required) — shell command to execute
- `working_dir` (string, optional) — working directory (defaults to first scoped path)

**Safety:**
- 30-second timeout
- stderr merged to stdout
- Working directory validated against sandbox
- Exit code reported on non-zero

## Path Sandbox

`Falcon.Chat.Tools.PathSandbox` enforces directory restrictions:

- **Absolute paths**: Must start with one of the allowed base paths
- **Relative paths**: Resolved against the first allowed base path, then validated
- **`~` expansion**: Home directory is expanded before validation
- **Traversal prevention**: `Path.expand/1` resolves `..` before checking containment

```elixir
# Example: thread scoped to /home/matt/Code/my-project
PathSandbox.resolve_path("src/main.ex", ["/home/matt/Code/my-project"])
# => {:ok, "/home/matt/Code/my-project/src/main.ex"}

PathSandbox.resolve_path("../../etc/passwd", ["/home/matt/Code/my-project"])
# => {:error, "Access denied: ..."}
```

## Tool Round Limits

The ThreadServer enforces a maximum of 20 tool call rounds per user message. This prevents infinite loops where the LLM repeatedly calls tools without producing a final response.

## Configuring Tools Per Thread

By default, all four tools are available when `scoped_paths` is set. Use `allowed_tools` to restrict:

```elixir
# Read-only agent
Chat.create_thread(%{
  model: "llama3.1:8b",
  user_id: user.id,
  scoped_paths: ["/home/matt/Code/my-project"],
  allowed_tools: ["read_file", "list_directory"]
})
```

## Adding New Tools

1. Add the tool definition to `@all_tools` in `Falcon.Chat.Tools`
2. Add a `execute_<tool_name>/2` function clause
3. The tool will automatically be available when `allowed_tools` is empty (all tools) or includes the new tool name
