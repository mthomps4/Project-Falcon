defmodule Falcon.Chat.ThreadServer do
  @moduledoc """
  GenServer managing a single chat thread's LLM interaction lifecycle.
  Handles streaming, tool calling, and state management.
  """
  use GenServer

  alias Falcon.Chat
  alias Falcon.Chat.Tools

  @max_tool_rounds 20
  @idle_timeout :timer.minutes(30)

  defstruct [:thread_id, :thread, :task, :buffer, :tool_round]

  # --- Client API ---

  def start_link(thread_id) do
    GenServer.start_link(__MODULE__, thread_id, name: via(thread_id))
  end

  def send_message(thread_id, content, opts \\ []) do
    ensure_started(thread_id)
    GenServer.call(via(thread_id), {:send_message, content, opts})
  end

  def stop(thread_id) do
    case Registry.lookup(Falcon.ThreadRegistry, thread_id) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> :ok
    end
  end

  def cancel(thread_id) do
    case Registry.lookup(Falcon.ThreadRegistry, thread_id) do
      [{pid, _}] -> GenServer.cast(pid, :cancel)
      [] -> :ok
    end
  end

  # --- Server Callbacks ---

  @impl true
  def init(thread_id) do
    thread = Chat.get_thread!(thread_id)

    {:ok, %__MODULE__{thread_id: thread_id, thread: thread, buffer: "", tool_round: 0},
     @idle_timeout}
  end

  @impl true
  def handle_call({:send_message, content, opts}, _from, state) do
    # Create user message
    {:ok, _user_msg} =
      Chat.create_message(%{
        thread_id: state.thread_id,
        role: "user",
        content: content,
        metadata: Keyword.get(opts, :metadata, %{})
      })

    # Start LLM streaming
    state = start_llm_stream(%{state | buffer: "", tool_round: 0})
    {:reply, :ok, state, @idle_timeout}
  end

  @impl true
  def handle_cast(:cancel, state) do
    # Kill the streaming task if running
    if state.task, do: Task.shutdown(state.task, :brutal_kill)

    # Save whatever was buffered
    if state.buffer != "" do
      Chat.create_message(%{
        thread_id: state.thread_id,
        role: "assistant",
        content: state.buffer <> "\n\n_(cancelled)_"
      })
    end

    Chat.update_thread_status(state.thread_id, "idle")

    Phoenix.PubSub.broadcast(
      Falcon.PubSub,
      "thread:#{state.thread_id}",
      :stream_done
    )

    {:noreply, %{state | buffer: "", task: nil}, @idle_timeout}
  end

  @impl true
  def handle_info({:llm_chunk, content}, state) do
    new_buffer = state.buffer <> content

    Phoenix.PubSub.broadcast(
      Falcon.PubSub,
      "thread:#{state.thread_id}",
      {:stream_chunk, content}
    )

    {:noreply, %{state | buffer: new_buffer}, @idle_timeout}
  end

  def handle_info(:llm_done, state) do
    # Check if the buffer contains an inline tool call (e.g. qwen2.5-coder)
    case parse_inline_tool_call(state.buffer) do
      {:tool_calls, tool_calls} ->
        # Treat it like a structured tool call
        send(self(), {:llm_tool_calls, tool_calls})
        {:noreply, %{state | buffer: "", task: nil}, @idle_timeout}

      :not_a_tool_call ->
        # Save the completed assistant message
        if state.buffer != "" do
          {:ok, _msg} =
            Chat.create_message(%{
              thread_id: state.thread_id,
              role: "assistant",
              content: state.buffer
            })
        end

        Chat.update_thread_status(state.thread_id, "idle")

        Phoenix.PubSub.broadcast(
          Falcon.PubSub,
          "thread:#{state.thread_id}",
          :stream_done
        )

        {:noreply, %{state | buffer: "", task: nil}, @idle_timeout}
    end
  end

  def handle_info({:llm_tool_calls, tool_calls}, state) do
    if state.tool_round >= @max_tool_rounds do
      Chat.update_thread_status(state.thread_id, "error")

      Phoenix.PubSub.broadcast(
        Falcon.PubSub,
        "thread:#{state.thread_id}",
        {:stream_error, "Max tool call rounds exceeded"}
      )

      {:noreply, %{state | task: nil}, @idle_timeout}
    else
      # Save assistant message with tool calls
      if state.buffer != "" do
        Chat.create_message(%{
          thread_id: state.thread_id,
          role: "assistant",
          content: state.buffer,
          metadata: %{"tool_calls" => tool_calls}
        })
      end

      # Execute tools and add results
      Enum.each(tool_calls, fn tool_call ->
        result = Tools.execute(tool_call, state.thread.scoped_paths)

        Chat.create_message(%{
          thread_id: state.thread_id,
          role: "tool",
          content: result,
          metadata: %{"tool_call" => tool_call}
        })
      end)

      # Loop back to LLM with tool results
      state = start_llm_stream(%{state | buffer: "", tool_round: state.tool_round + 1})
      {:noreply, state, @idle_timeout}
    end
  end

  def handle_info({:llm_error, reason}, state) do
    Chat.update_thread_status(state.thread_id, "error")

    Phoenix.PubSub.broadcast(
      Falcon.PubSub,
      "thread:#{state.thread_id}",
      {:stream_error, reason}
    )

    {:noreply, %{state | task: nil}, @idle_timeout}
  end

  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  def handle_info({ref, _result}, state) when is_reference(ref) do
    # Task completion message — ignore
    {:noreply, state, @idle_timeout}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state, @idle_timeout}
  end

  # --- Private ---

  defp start_llm_stream(state) do
    Chat.update_thread_status(state.thread_id, "active")
    messages = Chat.messages_for_llm(state.thread_id)

    # Prepend system prompt if configured
    messages =
      case state.thread.system_prompt do
        nil -> messages
        "" -> messages
        prompt -> [%{role: "system", content: prompt} | messages]
      end

    {module, config} = resolve_provider(state.thread)

    opts =
      [stream_to: self()]
      |> maybe_add_tools(state.thread)
      |> maybe_add_params(state.thread)

    {:ok, task} = module.stream_chat(config, messages, state.thread.model, opts)
    %{state | task: task}
  end

  defp resolve_provider(thread) do
    alias Falcon.LLM.ProviderRegistry

    case thread.provider_id do
      nil ->
        # Default to first Ollama provider
        ollama_url = Application.get_env(:falcon, :ollama_url, "http://localhost:11434")
        {Falcon.LLM.Ollama, %{base_url: ollama_url, api_key: nil}}

      provider_id ->
        provider = Falcon.Providers.get_provider!(provider_id)
        module = ProviderRegistry.module_for(provider.type) || Falcon.LLM.Ollama
        {module, ProviderRegistry.config_for(provider)}
    end
  end

  defp maybe_add_tools(opts, thread) do
    case thread.scoped_paths do
      [] ->
        opts

      nil ->
        opts

      paths ->
        tools = Tools.definitions(paths, thread.allowed_tools)
        Keyword.put(opts, :tools, tools)
    end
  end

  defp maybe_add_params(opts, thread) do
    params = thread.parameters || %{}

    opts
    |> maybe_put(:temperature, params["temperature"])
    |> maybe_put(:top_p, params["top_p"])
    |> maybe_put(:top_k, params["top_k"])
    |> maybe_put(:max_tokens, params["max_tokens"])
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, val), do: Keyword.put(opts, key, val)

  # Some models (e.g. qwen2.5-coder) emit tool calls as JSON in content
  # rather than using the structured tool_calls field
  defp parse_inline_tool_call(buffer) do
    trimmed = String.trim(buffer)

    case Jason.decode(trimmed) do
      {:ok, %{"name" => name, "arguments" => args}} when is_binary(name) ->
        tool_call = %{"function" => %{"name" => name, "arguments" => args}}
        {:tool_calls, [tool_call]}

      _ ->
        :not_a_tool_call
    end
  end

  defp ensure_started(thread_id) do
    case Registry.lookup(Falcon.ThreadRegistry, thread_id) do
      [{_pid, _}] ->
        :ok

      [] ->
        DynamicSupervisor.start_child(
          Falcon.ThreadSupervisor,
          {__MODULE__, thread_id}
        )
    end
  end

  defp via(thread_id) do
    {:via, Registry, {Falcon.ThreadRegistry, thread_id}}
  end
end
