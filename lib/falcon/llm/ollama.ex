defmodule Falcon.LLM.Ollama do
  @moduledoc """
  Ollama LLM provider. Communicates with a local or remote Ollama instance.
  """
  @behaviour Falcon.LLM

  @impl true
  def list_models(config) do
    url = config.base_url <> "/api/tags"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        {:ok,
         Enum.map(models, fn m ->
           %{
             id: m["model"],
             name: m["name"],
             provider: :ollama,
             size: m["size"],
             modified_at: m["modified_at"],
             details: m["details"]
           }
         end)}

      {:ok, %{status: status, body: body}} ->
        {:error, "Ollama returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def stream_chat(config, messages, model, opts \\ []) do
    stream_to = Keyword.fetch!(opts, :stream_to)
    url = config.base_url <> "/api/chat"

    body =
      %{
        model: model,
        messages: format_messages(messages),
        stream: true
      }
      |> maybe_add_options(opts)
      |> maybe_add_tools(opts)

    task =
      Task.async(fn ->
        try do
          Req.post!(url,
            json: body,
            connect_options: [timeout: 120_000],
            into: fn {:data, data}, acc ->
              data
              |> String.split("\n", trim: true)
              |> Enum.each(fn line ->
                case Jason.decode(line) do
                  {:ok, %{"message" => %{"content" => content}, "done" => false}} ->
                    send(stream_to, {:llm_chunk, content})

                  {:ok, %{"message" => %{"tool_calls" => tool_calls}, "done" => false}}
                  when tool_calls != [] ->
                    send(stream_to, {:llm_tool_calls, tool_calls})

                  {:ok, %{"done" => true}} ->
                    :ok

                  _ ->
                    :ok
                end
              end)

              {:cont, acc}
            end,
            receive_timeout: 300_000
          )

          send(stream_to, :llm_done)
        rescue
          e ->
            send(stream_to, {:llm_error, Exception.message(e)})
        end
      end)

    {:ok, task}
  end

  @impl true
  def supports?(_model, :vision), do: true
  def supports?(_model, :tool_calling), do: true
  def supports?(_model, _), do: false

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      base = %{"role" => msg.role, "content" => msg.content}

      case Map.get(msg, :images) do
        nil -> base
        [] -> base
        images -> Map.put(base, "images", images)
      end
    end)
  end

  defp maybe_add_options(body, opts) do
    options =
      Enum.reduce(opts, %{}, fn
        {:temperature, v}, acc -> Map.put(acc, :temperature, v)
        {:top_p, v}, acc -> Map.put(acc, :top_p, v)
        {:top_k, v}, acc -> Map.put(acc, :top_k, v)
        {:max_tokens, v}, acc -> Map.put(acc, :num_predict, v)
        _, acc -> acc
      end)

    if map_size(options) > 0, do: Map.put(body, :options, options), else: body
  end

  defp maybe_add_tools(body, opts) do
    case Keyword.get(opts, :tools) do
      nil -> body
      [] -> body
      tools -> Map.put(body, :tools, tools)
    end
  end

end
