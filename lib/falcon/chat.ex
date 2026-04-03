defmodule Falcon.Chat do
  @moduledoc """
  Context for managing chat threads and messages.
  """
  import Ecto.Query
  alias Falcon.Repo
  alias Falcon.Chat.{Thread, Message, Attachment}

  # --- Threads ---

  def list_threads(user_id, opts \\ []) do
    Thread
    |> where([t], t.user_id == ^user_id)
    |> where([t], is_nil(t.archived_at))
    |> order_by([t], desc: t.updated_at)
    |> maybe_limit(opts)
    |> Repo.all()
  end

  def get_thread!(id), do: Repo.get!(Thread, id)

  def get_thread_with_messages!(id) do
    Thread
    |> Repo.get!(id)
    |> Repo.preload(messages: from(m in Message, order_by: [asc: m.inserted_at]))
  end

  def create_thread(attrs) do
    %Thread{}
    |> Thread.changeset(attrs)
    |> Repo.insert()
  end

  def update_thread(%Thread{} = thread, attrs) do
    thread
    |> Thread.changeset(attrs)
    |> Repo.update()
  end

  def archive_thread(%Thread{} = thread) do
    update_thread(thread, %{archived_at: DateTime.utc_now()})
  end

  def delete_thread(%Thread{} = thread) do
    Repo.delete(thread)
  end

  def update_thread_status(thread_id, status) do
    Thread
    |> where([t], t.id == ^thread_id)
    |> Repo.update_all(set: [status: status, updated_at: DateTime.utc_now()])

    Phoenix.PubSub.broadcast(
      Falcon.PubSub,
      "thread:#{thread_id}",
      {:thread_status, status}
    )
  end

  # --- Messages ---

  def list_messages(thread_id) do
    Message
    |> where([m], m.thread_id == ^thread_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
    |> Repo.preload(:attachments)
  end

  def create_message(attrs) do
    result =
      %Message{}
      |> Message.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, message} ->
        Phoenix.PubSub.broadcast(
          Falcon.PubSub,
          "thread:#{message.thread_id}",
          {:new_message, message}
        )

        {:ok, message}

      error ->
        error
    end
  end

  def messages_for_llm(thread_id, opts \\ []) do
    max_messages = Keyword.get(opts, :max_messages, 100)

    Message
    |> where([m], m.thread_id == ^thread_id)
    |> order_by([m], asc: m.inserted_at)
    |> limit(^max_messages)
    |> Repo.all()
    |> Enum.map(fn m ->
      %{role: m.role, content: m.content}
    end)
  end

  # --- Attachments ---

  def create_attachment(attrs) do
    %Attachment{}
    |> Attachment.changeset(attrs)
    |> Repo.insert()
  end

  # --- Helpers ---

  defp maybe_limit(query, opts) do
    case Keyword.get(opts, :limit) do
      nil -> query
      limit -> limit(query, ^limit)
    end
  end
end
