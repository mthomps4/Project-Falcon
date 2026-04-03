defmodule Falcon.LLM.OpenAI do
  @moduledoc """
  OpenAI-compatible LLM provider. Works with OpenAI, Hugging Face TGI,
  LM Studio, vLLM, Groq, OpenRouter, and any OpenAI-compatible API.
  """
  @behaviour Falcon.LLM

  @impl true
  def list_models(config) do
    with {:ok, %{status: 200, body: body}} <-
           Req.get(config.base_url <> "/v1/models", headers: auth_headers(config)) do
      models =
        body
        |> Map.get("data", [])
        |> Enum.map(fn m ->
          %{
            id: m["id"],
            name: m["id"],
            provider: :openai,
            owned_by: m["owned_by"]
          }
        end)

      {:ok, models}
    else
      {:ok, %{status: status, body: body}} ->
        {:error, "OpenAI API returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def stream_chat(config, messages, model, opts \\ []) do
    stream_to = Keyword.fetch!(opts, :stream_to)

    body =
      %{
        model: model,
        messages: format_messages(messages),
        stream: true
      }
      |> maybe_add_params(opts)
      |> maybe_add_tools(opts)

    task =
      Task.async(fn ->
        try do
          Req.post!(config.base_url <> "/v1/chat/completions",
              json: body,
              headers: auth_headers(config),
              into: fn {:data, data}, acc ->
                data
                |> String.split("\n", trim: true)
                |> Enum.each(fn line ->
                  line = String.trim_leading(line, "data: ")
                  handle_sse_line(line, stream_to)
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

  defp handle_sse_line("[DONE]", _stream_to), do: :ok

  defp handle_sse_line(line, stream_to) do
    case Jason.decode(line) do
      {:ok, %{"choices" => [%{"delta" => delta} | _]}} ->
        if content = delta["content"] do
          send(stream_to, {:llm_chunk, content})
        end

        if tool_calls = delta["tool_calls"] do
          send(stream_to, {:llm_tool_calls, tool_calls})
        end

      _ ->
        :ok
    end
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      case Map.get(msg, :images) do
        nil ->
          %{"role" => msg.role, "content" => msg.content}

        [] ->
          %{"role" => msg.role, "content" => msg.content}

        images ->
          content =
            [%{"type" => "text", "text" => msg.content}] ++
              Enum.map(images, fn img ->
                %{
                  "type" => "image_url",
                  "image_url" => %{"url" => "data:image/png;base64,#{img}"}
                }
              end)

          %{"role" => msg.role, "content" => content}
      end
    end)
  end

  defp maybe_add_params(body, opts) do
    Enum.reduce(opts, body, fn
      {:temperature, v}, acc -> Map.put(acc, :temperature, v)
      {:top_p, v}, acc -> Map.put(acc, :top_p, v)
      {:max_tokens, v}, acc -> Map.put(acc, :max_tokens, v)
      _, acc -> acc
    end)
  end

  defp maybe_add_tools(body, opts) do
    case Keyword.get(opts, :tools) do
      nil -> body
      [] -> body
      tools -> Map.put(body, :tools, tools)
    end
  end

  defp auth_headers(config) do
    case config.api_key do
      nil -> []
      key -> [{"authorization", "Bearer #{key}"}]
    end
  end

end
