defmodule Falcon.Chat.Tools do
  @moduledoc """
  Registry and dispatcher for agent tools. Tools provide file system and
  command execution capabilities within sandboxed directories.
  """

  alias Falcon.Chat.Tools.PathSandbox

  @all_tools %{
    "read_file" => %{
      name: "read_file",
      description: "Read the contents of a file at the given path.",
      parameters: %{
        type: "object",
        properties: %{
          path: %{type: "string", description: "Path to the file to read"}
        },
        required: ["path"]
      }
    },
    "write_file" => %{
      name: "write_file",
      description:
        "Write content to a file at the given path. Creates the file if it doesn't exist.",
      parameters: %{
        type: "object",
        properties: %{
          path: %{type: "string", description: "Path to the file to write"},
          content: %{type: "string", description: "Content to write to the file"}
        },
        required: ["path", "content"]
      }
    },
    "list_directory" => %{
      name: "list_directory",
      description: "List files and directories at the given path.",
      parameters: %{
        type: "object",
        properties: %{
          path: %{type: "string", description: "Directory path to list"}
        },
        required: ["path"]
      }
    },
    "run_command" => %{
      name: "run_command",
      description: "Run a shell command in the specified working directory.",
      parameters: %{
        type: "object",
        properties: %{
          command: %{type: "string", description: "Shell command to execute"},
          working_dir: %{type: "string", description: "Working directory for the command"}
        },
        required: ["command"]
      }
    }
  }

  @doc "Return tool definitions for the given paths and allowed tools."
  def definitions([], _allowed_tools), do: []
  def definitions(nil, _allowed_tools), do: []

  def definitions(paths, allowed_tools) when is_list(paths) do
    tools =
      case allowed_tools do
        nil -> Map.values(@all_tools)
        [] -> Map.values(@all_tools)
        names -> names |> Enum.map(&Map.get(@all_tools, &1)) |> Enum.reject(&is_nil/1)
      end

    # Format for Ollama/OpenAI tool calling
    Enum.map(tools, fn tool ->
      %{
        type: "function",
        function: tool
      }
    end)
  end

  @doc "Execute a tool call within the sandbox."
  def execute(tool_call, scoped_paths) do
    name = get_tool_name(tool_call)
    args = get_tool_args(tool_call)

    case name do
      "read_file" -> execute_read_file(args, scoped_paths)
      "write_file" -> execute_write_file(args, scoped_paths)
      "list_directory" -> execute_list_directory(args, scoped_paths)
      "run_command" -> execute_run_command(args, scoped_paths)
      _ -> "Unknown tool: #{name}"
    end
  end

  defp execute_read_file(%{"path" => path}, scoped_paths) do
    with {:ok, resolved} <- PathSandbox.resolve_path(path, scoped_paths) do
      case File.read(resolved) do
        {:ok, content} -> content
        {:error, reason} -> "Error reading file: #{reason}"
      end
    else
      {:error, msg} -> msg
    end
  end

  defp execute_write_file(%{"path" => path, "content" => content}, scoped_paths) do
    with {:ok, resolved} <- PathSandbox.resolve_path(path, scoped_paths) do
      File.mkdir_p!(Path.dirname(resolved))

      case File.write(resolved, content) do
        :ok -> "File written successfully: #{resolved}"
        {:error, reason} -> "Error writing file: #{reason}"
      end
    else
      {:error, msg} -> msg
    end
  end

  defp execute_list_directory(%{"path" => path}, scoped_paths) do
    with {:ok, resolved} <- PathSandbox.resolve_path(path, scoped_paths) do
      case File.ls(resolved) do
        {:ok, entries} ->
          entries
          |> Enum.sort()
          |> Enum.map_join("\n", fn entry ->
            full = Path.join(resolved, entry)
            type = if File.dir?(full), do: "dir", else: "file"
            "#{type}\t#{entry}"
          end)

        {:error, reason} ->
          "Error listing directory: #{reason}"
      end
    else
      {:error, msg} -> msg
    end
  end

  defp execute_run_command(%{"command" => command} = args, scoped_paths) do
    working_dir = Map.get(args, "working_dir")

    dir =
      case working_dir do
        nil ->
          case scoped_paths do
            [first | _] -> Path.expand(first)
            _ -> System.tmp_dir!()
          end

        wd ->
          case PathSandbox.resolve_path(wd, scoped_paths) do
            {:ok, resolved} -> resolved
            {:error, _} -> nil
          end
      end

    if dir do
      case System.cmd("sh", ["-c", command], cd: dir, stderr_to_stdout: true, timeout: 30_000) do
        {output, 0} -> output
        {output, code} -> "Command exited with code #{code}:\n#{output}"
      end
    else
      "Access denied: working directory outside allowed paths"
    end
  rescue
    e -> "Command error: #{Exception.message(e)}"
  end

  # Handle both Ollama and OpenAI tool call formats
  defp get_tool_name(%{"function" => %{"name" => name}}), do: name
  defp get_tool_name(%{"name" => name}), do: name

  defp get_tool_args(%{"function" => %{"arguments" => args}}) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      _ -> %{}
    end
  end

  defp get_tool_args(%{"function" => %{"arguments" => args}}) when is_map(args), do: args

  defp get_tool_args(%{"arguments" => args}) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      _ -> %{}
    end
  end

  defp get_tool_args(%{"arguments" => args}) when is_map(args), do: args
  defp get_tool_args(_), do: %{}
end
