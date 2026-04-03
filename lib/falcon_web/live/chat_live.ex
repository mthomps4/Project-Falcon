defmodule FalconWeb.ChatLive do
  use FalconWeb, :live_view

  alias Falcon.Chat
  alias Falcon.Chat.ThreadServer
  alias Falcon.Providers

  import FalconWeb.Layouts, only: [theme_toggle: 1, flash_group: 1]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    threads = Chat.list_threads(user.id)
    models = load_models()

    Providers.ensure_default_ollama!()

    {:ok,
     socket
     |> assign(:threads, threads)
     |> assign(:models, models)
     |> assign(:current_thread, nil)
     |> assign(:messages, [])
     |> assign(:streaming, false)
     |> assign(:stream_buffer, "")
     |> assign(:message_input, "")
     |> assign(:show_new_thread_modal, false)
     |> assign(:sidebar_collapsed, false)
     |> assign(:editing_thread_id, nil)
     |> assign(:mobile_sidebar_open, false)
     |> assign(:page_title, "FALCON")}
  end

  @impl true
  def handle_params(%{"thread_id" => thread_id}, _uri, socket) do
    user = socket.assigns.current_scope.user
    thread = Chat.get_thread!(thread_id)

    if thread.user_id != user.id do
      {:noreply, push_navigate(socket, to: ~p"/chat")}
    else
      if old = socket.assigns.current_thread do
        Phoenix.PubSub.unsubscribe(Falcon.PubSub, "thread:#{old.id}")
      end

      Phoenix.PubSub.subscribe(Falcon.PubSub, "thread:#{thread_id}")
      messages = Chat.list_messages(thread_id)

      {:noreply,
       socket
       |> assign(:current_thread, thread)
       |> assign(:messages, messages)
       |> assign(:streaming, thread.status == "active")
       |> assign(:stream_buffer, "")
       |> assign(:page_title, thread.title || "New Chat")}
    end
  end

  def handle_params(_params, _uri, socket) do
    if old = socket.assigns.current_thread do
      Phoenix.PubSub.unsubscribe(Falcon.PubSub, "thread:#{old.id}")
    end

    {:noreply,
     socket
     |> assign(:current_thread, nil)
     |> assign(:messages, [])
     |> assign(:streaming, false)
     |> assign(:stream_buffer, "")}
  end

  # --- Events ---

  @impl true
  def handle_event("new_thread", _params, socket) do
    {:noreply, assign(socket, :show_new_thread_modal, true)}
  end

  def handle_event("create_thread", params, socket) do
    user = socket.assigns.current_scope.user
    {provider_id, model} = parse_model_selection(params["model"])

    title = case String.trim(params["title"] || "") do
      "" -> nil
      t -> t
    end

    attrs = %{
      model: model,
      provider_id: provider_id,
      user_id: user.id,
      title: title,
      system_prompt: params["system_prompt"],
      scoped_paths: parse_paths(params["scoped_paths"]),
      allowed_tools: parse_tools(params["allowed_tools"]),
      parameters: parse_parameters(params)
    }

    case Chat.create_thread(attrs) do
      {:ok, thread} ->
        threads = Chat.list_threads(user.id)

        {:noreply,
         socket
         |> assign(:threads, threads)
         |> assign(:show_new_thread_modal, false)
         |> push_patch(to: ~p"/chat/#{thread.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create thread")}
    end
  end

  def handle_event("send_message", %{"message" => content}, socket) when content != "" do
    thread = socket.assigns.current_thread

    if thread && !socket.assigns.streaming do
      ThreadServer.send_message(thread.id, content)
      messages = Chat.list_messages(thread.id)

      {:noreply,
       socket
       |> assign(:messages, messages)
       |> assign(:streaming, true)
       |> assign(:stream_buffer, "")
       |> assign(:message_input, "")
       |> push_event("scroll-bottom", %{})
       |> push_event("clear-input", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_stream", _params, socket) do
    if thread = socket.assigns.current_thread do
      ThreadServer.cancel(thread.id)
    end

    messages = if socket.assigns.current_thread,
      do: Chat.list_messages(socket.assigns.current_thread.id),
      else: []

    {:noreply,
     socket
     |> assign(:streaming, false)
     |> assign(:stream_buffer, "")
     |> assign(:messages, messages)}
  end

  def handle_event("select_thread", %{"id" => thread_id}, socket) do
    {:noreply,
     socket
     |> assign(:mobile_sidebar_open, false)
     |> push_patch(to: ~p"/chat/#{thread_id}")}
  end

  def handle_event("start_rename", %{"id" => thread_id}, socket) do
    {:noreply, assign(socket, :editing_thread_id, thread_id)}
  end

  def handle_event("save_rename", %{"thread_id" => thread_id, "title" => title}, socket) do
    thread = Chat.get_thread!(thread_id)
    title = String.trim(title)
    title = if title == "", do: nil, else: title
    {:ok, thread} = Chat.update_thread(thread, %{title: title})

    user = socket.assigns.current_scope.user
    threads = Chat.list_threads(user.id)

    current_thread =
      if socket.assigns.current_thread && socket.assigns.current_thread.id == thread_id do
        thread
      else
        socket.assigns.current_thread
      end

    {:noreply,
     socket
     |> assign(:threads, threads)
     |> assign(:current_thread, current_thread)
     |> assign(:editing_thread_id, nil)}
  end

  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, :editing_thread_id, nil)}
  end

  def handle_event("archive_thread", %{"id" => thread_id}, socket) do
    thread = Chat.get_thread!(thread_id)
    Chat.archive_thread(thread)
    user = socket.assigns.current_scope.user
    threads = Chat.list_threads(user.id)

    socket =
      if socket.assigns.current_thread && socket.assigns.current_thread.id == thread_id do
        push_patch(socket, to: ~p"/chat")
      else
        socket
      end

    {:noreply, assign(socket, :threads, threads)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :show_new_thread_modal, false)}
  end

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :sidebar_collapsed, !socket.assigns.sidebar_collapsed)}
  end

  def handle_event("toggle_mobile_sidebar", _params, socket) do
    {:noreply, assign(socket, :mobile_sidebar_open, !socket.assigns.mobile_sidebar_open)}
  end


  # --- PubSub Handlers ---

  @impl true
  def handle_info({:stream_chunk, content}, socket) do
    {:noreply,
     socket
     |> assign(:stream_buffer, socket.assigns.stream_buffer <> content)
     |> push_event("scroll-bottom", %{})}
  end

  def handle_info(:stream_done, socket) do
    messages = Chat.list_messages(socket.assigns.current_thread.id)
    thread = Chat.get_thread!(socket.assigns.current_thread.id)

    thread =
      if is_nil(thread.title) && length(messages) >= 2 do
        title =
          messages
          |> Enum.find(&(&1.role == "user"))
          |> case do
            nil -> "New Chat"
            msg -> String.slice(msg.content, 0, 60)
          end

        {:ok, thread} = Chat.update_thread(thread, %{title: title})
        thread
      else
        thread
      end

    user = socket.assigns.current_scope.user
    threads = Chat.list_threads(user.id)

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:streaming, false)
     |> assign(:stream_buffer, "")
     |> assign(:current_thread, thread)
     |> assign(:threads, threads)
     |> push_event("scroll-bottom", %{})}
  end

  def handle_info({:stream_error, reason}, socket) do
    {:noreply,
     socket
     |> assign(:streaming, false)
     |> assign(:stream_buffer, "")
     |> put_flash(:error, "LLM Error: #{reason}")}
  end

  def handle_info({:new_message, _message}, socket), do: {:noreply, socket}
  def handle_info({:thread_status, _status}, socket), do: {:noreply, socket}

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-dvh overflow-hidden">
      <%!-- ==================== MOBILE SIDEBAR OVERLAY ==================== --%>
      <div
        :if={@mobile_sidebar_open}
        class="fixed inset-0 z-40 md:hidden"
      >
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="toggle_mobile_sidebar"></div>
        <aside class="absolute left-0 top-0 bottom-0 w-72 flex flex-col bg-base-200 border-r border-base-300/50 shadow-2xl">
          <%!-- Logo Area --%>
          <div class="p-4 border-b border-base-300/30">
            <div class="flex items-center gap-3">
              <button phx-click="toggle_mobile_sidebar" class="flex-shrink-0 cursor-pointer group">
                <img src={~p"/images/falcon-icon.svg"} class="w-8 h-8 transition-transform group-hover:scale-110" />
              </button>
              <div class="flex items-center justify-between flex-1 min-w-0">
                <span class="text-lg font-bold tracking-wider falcon-gradient-text">FALCON</span>
                <.theme_toggle />
              </div>
            </div>
          </div>
          <%!-- New Chat --%>
          <div class="p-3">
            <button phx-click="new_thread" class="btn btn-primary w-full gap-2 shadow-lg transition-all duration-200 hover:shadow-primary/25 hover:scale-[1.02] active:scale-[0.98]">
              <.icon name="hero-plus" class="size-5" />
              <span>New Chat</span>
            </button>
          </div>
          <%!-- Thread List --%>
          <nav class="flex-1 overflow-y-auto falcon-scrollbar px-2 space-y-0.5">
            <div
              :for={thread <- @threads}
              class={["falcon-sidebar-item group rounded-lg px-3 py-2.5 cursor-pointer", @current_thread && @current_thread.id == thread.id && "active"]}
              phx-click="select_thread"
              phx-value-id={thread.id}
            >
              <div class="flex items-center justify-between">
                <div class="truncate flex-1 min-w-0">
                  <div class="text-sm font-medium truncate">{thread.title || "New Chat"}</div>
                  <div class="flex items-center gap-1.5 mt-0.5">
                    <span class="text-[10px] opacity-40 truncate">{thread.model}</span>
                    <span :if={thread.scoped_paths != []} class="inline-flex items-center gap-0.5 text-[10px] text-secondary opacity-60">
                      <.icon name="hero-folder-micro" class="size-2.5" />
                    </span>
                  </div>
                </div>
              </div>
            </div>
            <div :if={@threads == []} class="text-center py-12 px-4">
              <.icon name="hero-chat-bubble-left-right" class="size-8 opacity-20 mx-auto mb-2" />
              <p class="text-xs opacity-30">No conversations yet</p>
            </div>
          </nav>
          <%!-- REPL + User --%>
          <div class="px-3 pb-1">
            <a href="http://arch:4001" target="_blank" class="flex items-center gap-2 px-3 py-2 rounded-lg text-secondary/60 hover:text-secondary hover:bg-secondary/10 transition-all duration-200">
              <.icon name="hero-command-line" class="size-4" />
              <span class="text-xs font-mono">REPL</span>
              <.icon name="hero-arrow-top-right-on-square-micro" class="size-3 opacity-40" />
            </a>
          </div>
          <div class="p-3 border-t border-base-300/30">
            <div class="flex items-center gap-2">
              <div class="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0">
                <span class="text-xs font-bold text-primary">{String.first(@current_scope.user.email) |> String.upcase()}</span>
              </div>
              <div class="flex items-center justify-between flex-1 min-w-0">
                <span class="text-xs truncate opacity-50">{@current_scope.user.email}</span>
                <.link href={~p"/users/log-out"} method="delete" class="opacity-30 hover:opacity-80 transition-opacity p-1" title="Log out">
                  <.icon name="hero-arrow-right-start-on-rectangle-micro" class="size-4" />
                </.link>
              </div>
            </div>
          </div>
        </aside>
      </div>

      <%!-- ==================== DESKTOP SIDEBAR ==================== --%>
      <aside class={[
        "hidden md:flex flex-col border-r border-base-300/50 bg-base-200 transition-all duration-300 ease-in-out flex-shrink-0",
        if(@sidebar_collapsed, do: "w-16", else: "w-72")
      ]}>
        <%!-- Logo Area --%>
        <div class="p-4 border-b border-base-300/30">
          <div class="flex items-center gap-3">
            <button phx-click="toggle_sidebar" class="flex-shrink-0 cursor-pointer group">
              <img
                src={~p"/images/falcon-icon.svg"}
                class="w-8 h-8 transition-transform group-hover:scale-110"
              />
            </button>
            <div :if={!@sidebar_collapsed} class="flex items-center justify-between flex-1 min-w-0">
              <span class="text-lg font-bold tracking-wider falcon-gradient-text">FALCON</span>
              <.theme_toggle />
            </div>
          </div>
        </div>

        <%!-- New Chat Button --%>
        <div class="p-3">
          <button
            phx-click="new_thread"
            class={[
              "btn btn-primary w-full gap-2 shadow-lg transition-all duration-200",
              "hover:shadow-primary/25 hover:scale-[1.02] active:scale-[0.98]",
              if(@sidebar_collapsed, do: "btn-square", else: "")
            ]}
          >
            <.icon name="hero-plus" class="size-5" />
            <span :if={!@sidebar_collapsed}>New Chat</span>
          </button>
        </div>

        <%!-- Thread List --%>
        <nav class="flex-1 overflow-y-auto falcon-scrollbar px-2 space-y-0.5">
          <div
            :for={thread <- @threads}
            class={[
              "falcon-sidebar-item group rounded-lg px-3 py-2.5 cursor-pointer",
              @current_thread && @current_thread.id == thread.id && "active"
            ]}
            phx-click="select_thread"
            phx-value-id={thread.id}
          >
            <div :if={!@sidebar_collapsed} class="flex items-center justify-between">
              <div class="truncate flex-1 min-w-0">
                <div class="text-sm font-medium truncate">{thread.title || "New Chat"}</div>
                <div class="flex items-center gap-1.5 mt-0.5">
                  <span class="text-[10px] opacity-40 truncate">{thread.model}</span>
                  <span
                    :if={thread.scoped_paths != []}
                    class="inline-flex items-center gap-0.5 text-[10px] text-secondary opacity-60"
                  >
                    <.icon name="hero-folder-micro" class="size-2.5" />
                  </span>
                </div>
              </div>
              <button
                phx-click="archive_thread"
                phx-value-id={thread.id}
                class="opacity-0 group-hover:opacity-50 hover:!opacity-100 transition-opacity ml-2 p-1 rounded hover:bg-base-300/50"
                title="Archive"
              >
                <.icon name="hero-archive-box-micro" class="size-3.5" />
              </button>
            </div>
            <div
              :if={@sidebar_collapsed}
              class="flex justify-center"
              title={thread.title || "New Chat"}
            >
              <.icon name="hero-chat-bubble-left-micro" class="size-5 opacity-60" />
            </div>
          </div>

          <div :if={@threads == []} class="text-center py-12 px-4">
            <div :if={!@sidebar_collapsed}>
              <.icon name="hero-chat-bubble-left-right" class="size-8 opacity-20 mx-auto mb-2" />
              <p class="text-xs opacity-30">No conversations yet</p>
            </div>
          </div>
        </nav>

        <%!-- REPL Link --%>
        <div class="px-3 pb-1">
          <a
            href="http://arch:4001"
            target="_blank"
            class="flex items-center gap-2 px-3 py-2 rounded-lg text-secondary/60 hover:text-secondary hover:bg-secondary/10 transition-all duration-200"
          >
            <.icon name="hero-command-line" class="size-4" />
            <span :if={!@sidebar_collapsed} class="text-xs font-mono">REPL</span>
            <.icon :if={!@sidebar_collapsed} name="hero-arrow-top-right-on-square-micro" class="size-3 opacity-40" />
          </a>
        </div>

        <%!-- User Footer --%>
        <div class="p-3 border-t border-base-300/30">
          <div class="flex items-center gap-2">
            <div class="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0">
              <span class="text-xs font-bold text-primary">
                {String.first(@current_scope.user.email) |> String.upcase()}
              </span>
            </div>
            <div :if={!@sidebar_collapsed} class="flex items-center justify-between flex-1 min-w-0">
              <span class="text-xs truncate opacity-50">{@current_scope.user.email}</span>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="opacity-30 hover:opacity-80 transition-opacity p-1"
                title="Log out"
              >
                <.icon name="hero-arrow-right-start-on-rectangle-micro" class="size-4" />
              </.link>
            </div>
          </div>
        </div>
      </aside>

      <%!-- ==================== MAIN CONTENT ==================== --%>
      <main class="flex-1 flex flex-col min-w-0 min-h-0 bg-base-100">
        <%!-- Active Thread View --%>
        <div :if={@current_thread} class="flex flex-col h-full">
          <%!-- Thread Header (sticky) --%>
          <header class="flex-shrink-0 px-4 md:px-6 py-3 border-b border-base-300/30 flex items-center gap-3 bg-base-100/80 backdrop-blur-sm">
            <%!-- Mobile menu button --%>
            <button phx-click="toggle_mobile_sidebar" class="md:hidden p-1 rounded-lg hover:bg-base-200 transition-colors">
              <.icon name="hero-bars-3" class="size-5" />
            </button>
            <div class="flex-1 min-w-0">
              <%!-- Inline rename --%>
              <form
                :if={@editing_thread_id == @current_thread.id}
                phx-submit="save_rename"
                phx-click-away="cancel_rename"
                class="flex items-center gap-2"
              >
                <input type="hidden" name="thread_id" value={@current_thread.id} />
                <input
                  type="text"
                  name="title"
                  value={@current_thread.title || ""}
                  class="input input-sm input-bordered bg-base-200/50 text-sm font-semibold w-full max-w-64"
                  autofocus
                  phx-key="escape"
                  phx-keydown="cancel_rename"
                />
                <button type="submit" class="p-1 rounded hover:bg-base-300/50 opacity-50 hover:opacity-100 transition-opacity" title="Save">
                  <.icon name="hero-check-micro" class="size-4 text-success" />
                </button>
                <button type="button" phx-click="cancel_rename" class="p-1 rounded hover:bg-base-300/50 opacity-50 hover:opacity-100 transition-opacity" title="Cancel">
                  <.icon name="hero-x-mark-micro" class="size-4" />
                </button>
              </form>
              <%!-- Normal display --%>
              <div :if={@editing_thread_id != @current_thread.id} class="flex items-center gap-2">
                <h2 class="font-semibold text-sm truncate">{@current_thread.title || "New Chat"}</h2>
                <button
                  phx-click="start_rename"
                  phx-value-id={@current_thread.id}
                  class="opacity-30 hover:opacity-80 transition-opacity p-0.5 rounded hover:bg-base-300/50 flex-shrink-0"
                  title="Rename"
                >
                  <.icon name="hero-pencil-square-micro" class="size-3.5" />
                </button>
              </div>
              <div class="flex items-center gap-2 mt-0.5 flex-wrap">
                <span class="inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full bg-primary/10 text-primary">
                  <.icon name="hero-cpu-chip-micro" class="size-3" />
                  {@current_thread.model}
                </span>
                <span
                  :if={@current_thread.scoped_paths != []}
                  class="inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full bg-secondary/10 text-secondary"
                >
                  <.icon name="hero-folder-micro" class="size-3" />
                  {length(@current_thread.scoped_paths)} path(s)
                </span>
                <span
                  :if={@current_thread.system_prompt && @current_thread.system_prompt != ""}
                  class="hidden sm:inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full bg-accent/10 text-accent"
                >
                  <.icon name="hero-document-text-micro" class="size-3" /> Prompt
                </span>
              </div>
            </div>
            <div
              :if={@streaming}
              class="flex items-center gap-2 text-xs text-secondary flex-shrink-0"
            >
              <span class="relative flex h-2.5 w-2.5">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-secondary opacity-75">
                </span>
                <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-secondary falcon-pulse">
                </span>
              </span>
              <span class="hidden sm:inline">Generating</span>
            </div>
          </header>

          <%!-- Messages Container (scrollable) --%>
          <div
            id="messages"
            class="flex-1 overflow-y-auto falcon-scrollbar"
            style="min-height: 0"
            phx-hook="ScrollBottom"
          >
            <div class="max-w-3xl mx-auto px-4 md:px-6 py-6 space-y-6">
              <%!-- System prompt indicator --%>
              <div
                :if={@current_thread.system_prompt && @current_thread.system_prompt != ""}
                class="flex justify-center"
              >
                <div class="text-[11px] opacity-30 flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-base-200/50">
                  <.icon name="hero-document-text-micro" class="size-3" /> System prompt configured
                </div>
              </div>

              <%!-- Messages --%>
              <div
                :for={msg <- @messages}
                class={[
                  "falcon-message-in",
                  msg.role == "user" && "flex justify-end",
                  msg.role in ["assistant", "system"] && "flex justify-start",
                  msg.role == "tool" && "flex justify-start"
                ]}
              >
                <%!-- User Message --%>
                <div :if={msg.role == "user"} class="max-w-[85%] md:max-w-[75%]">
                  <div class="rounded-2xl rounded-br-md px-4 py-2.5 bg-primary text-primary-content">
                    <div class="text-sm whitespace-pre-wrap">{msg.content}</div>
                  </div>
                </div>

                <%!-- Assistant Message --%>
                <div :if={msg.role == "assistant"} class="max-w-[95%] md:max-w-[85%] flex gap-2 md:gap-3">
                  <div class="w-7 h-7 rounded-lg bg-base-200 flex items-center justify-center flex-shrink-0 mt-1 falcon-border-glow">
                    <img src={~p"/images/falcon-icon.svg"} class="w-4 h-4" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="rounded-2xl rounded-tl-md px-4 py-3 bg-base-200/70">
                      <div class="falcon-prose text-sm">{raw(render_markdown(msg.content))}</div>
                    </div>
                  </div>
                </div>

                <%!-- Tool Result --%>
                <div :if={msg.role == "tool"} class="max-w-[95%] md:max-w-[85%] flex gap-2 md:gap-3">
                  <div class="w-7 h-7 rounded-lg bg-secondary/10 flex items-center justify-center flex-shrink-0 mt-1">
                    <.icon name="hero-wrench-screwdriver-micro" class="size-3.5 text-secondary" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="rounded-xl px-3 py-2 bg-base-300/50 border border-base-300/50">
                      <pre class="text-[11px] font-mono whitespace-pre-wrap text-base-content/70 overflow-x-auto">{msg.content}</pre>
                    </div>
                  </div>
                </div>

                <%!-- System Message --%>
                <div :if={msg.role == "system"} class="w-full flex justify-center">
                  <div class="text-xs italic opacity-40 px-4 py-2">{msg.content}</div>
                </div>
              </div>

              <%!-- Streaming Response --%>
              <div :if={@streaming} class="flex justify-start">
                <div class="max-w-[95%] md:max-w-[85%] flex gap-2 md:gap-3">
                  <div class="w-7 h-7 rounded-lg bg-base-200 flex items-center justify-center flex-shrink-0 mt-1 falcon-pulse">
                    <img src={~p"/images/falcon-icon.svg"} class="w-4 h-4" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div
                      :if={@stream_buffer != ""}
                      class="rounded-2xl rounded-tl-md px-4 py-3 bg-base-200/70"
                    >
                      <div class="falcon-prose text-sm falcon-cursor">
                        {raw(render_markdown(@stream_buffer))}
                      </div>
                    </div>
                    <div
                      :if={@stream_buffer == ""}
                      class="rounded-2xl rounded-tl-md px-4 py-3 bg-base-200/70"
                    >
                      <div class="flex items-center gap-1.5">
                        <span class="w-1.5 h-1.5 rounded-full bg-secondary animate-bounce [animation-delay:0ms]">
                        </span>
                        <span class="w-1.5 h-1.5 rounded-full bg-secondary animate-bounce [animation-delay:150ms]">
                        </span>
                        <span class="w-1.5 h-1.5 rounded-full bg-secondary animate-bounce [animation-delay:300ms]">
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <%!-- Input Area (sticky bottom) --%>
          <div class="flex-shrink-0 border-t border-base-300/30 bg-base-100">
            <div class="max-w-3xl mx-auto px-4 md:px-6 py-3 md:py-4">
              <form phx-submit="send_message" class="relative">
                <div class="falcon-border-glow rounded-2xl bg-base-200/50 overflow-hidden flex items-end">
                  <textarea
                    name="message"
                    placeholder={
                      if(@streaming, do: "Waiting for response...", else: "Message FALCON...")
                    }
                    class="flex-1 bg-transparent border-none px-4 md:px-5 py-3 md:py-4 text-sm placeholder:opacity-30 falcon-input focus:ring-0 focus:outline-none resize-none max-h-40 overflow-y-auto"
                    autocomplete="off"
                    disabled={@streaming}
                    id="message-input"
                    phx-hook="MessageInput"
                    rows="1"
                  ></textarea>
                  <button
                    :if={!@streaming}
                    type="submit"
                    class="mr-3 p-2 rounded-xl transition-all duration-200 bg-primary text-primary-content hover:shadow-lg hover:shadow-primary/25 hover:scale-105 active:scale-95"
                  >
                    <.icon name="hero-paper-airplane" class="size-4" />
                  </button>
                  <button
                    :if={@streaming}
                    type="button"
                    phx-click="cancel_stream"
                    class="mr-3 p-2 rounded-xl transition-all duration-200 bg-error text-error-content hover:shadow-lg hover:shadow-error/25 hover:scale-105 active:scale-95"
                  >
                    <.icon name="hero-stop" class="size-4" />
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>

        <%!-- ==================== EMPTY STATE ==================== --%>
        <div :if={!@current_thread} class="flex-1 flex flex-col min-h-0">
          <%!-- Mobile header for empty state --%>
          <div class="md:hidden flex-shrink-0 px-4 py-3 border-b border-base-300/30">
            <button phx-click="toggle_mobile_sidebar" class="p-1 rounded-lg hover:bg-base-200 transition-colors">
              <.icon name="hero-bars-3" class="size-5" />
            </button>
          </div>
          <div class="flex-1 flex items-center justify-center">
            <div class="text-center space-y-6 max-w-md px-6">
              <div class="relative inline-block">
                <img src={~p"/images/logo.svg"} class="w-28 h-28 mx-auto" />
                <div class="absolute inset-0 w-28 h-28 mx-auto rounded-full bg-primary/5 blur-2xl">
                </div>
              </div>
              <div>
                <h2 class="text-3xl font-bold tracking-wider falcon-gradient-text mb-2">FALCON</h2>
                <p class="text-sm opacity-40 leading-relaxed">
                  Your personal AI assistant. Start a conversation, choose a model,
                  and optionally scope it to a project folder for agent-powered code work.
                </p>
              </div>
              <div class="grid grid-cols-2 gap-3 text-left">
                <button
                  phx-click="new_thread"
                  class="p-4 rounded-xl bg-base-200/50 hover:bg-base-200 transition-all falcon-border-glow text-left group"
                >
                  <.icon
                    name="hero-chat-bubble-left-right"
                    class="size-5 text-primary mb-2 group-hover:scale-110 transition-transform"
                  />
                  <div class="text-xs font-medium">New Chat</div>
                  <div class="text-[10px] opacity-40 mt-0.5">Start a conversation</div>
                </button>
                <button
                  phx-click="new_thread"
                  class="p-4 rounded-xl bg-base-200/50 hover:bg-base-200 transition-all falcon-border-glow text-left group"
                >
                  <.icon
                    name="hero-folder-open"
                    class="size-5 text-secondary mb-2 group-hover:scale-110 transition-transform"
                  />
                  <div class="text-xs font-medium">Code Agent</div>
                  <div class="text-[10px] opacity-40 mt-0.5">Scope to a project folder</div>
                </button>
              </div>

              <div :if={@models != []} class="pt-2">
                <p class="text-[10px] opacity-25 mb-2">
                  {length(@models)} model(s) available
                </p>
                <div class="flex flex-wrap justify-center gap-1.5">
                  <span
                    :for={model <- Enum.take(@models, 6)}
                    class="text-[10px] px-2 py-0.5 rounded-full bg-base-200/50 opacity-30"
                  >
                    {model.name}
                  </span>
                  <span :if={length(@models) > 6} class="text-[10px] px-2 py-0.5 opacity-20">
                    +{length(@models) - 6} more
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </main>

      <%!-- ==================== NEW THREAD MODAL ==================== --%>
      <div
        :if={@show_new_thread_modal}
        class="fixed inset-0 z-50 flex items-center justify-center"
      >
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="close_modal"></div>
        <div class="relative w-full max-w-lg mx-4 rounded-2xl bg-base-100 border border-base-300/50 shadow-2xl falcon-glow overflow-hidden">
          <%!-- Modal Header --%>
          <div class="px-6 py-4 border-b border-base-300/30 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <div class="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
                <.icon name="hero-plus" class="size-4 text-primary" />
              </div>
              <h3 class="font-semibold">New Chat</h3>
            </div>
            <button
              phx-click="close_modal"
              class="p-1.5 rounded-lg hover:bg-base-200 transition-colors opacity-50 hover:opacity-100"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <%!-- Modal Body --%>
          <form phx-submit="create_thread" class="p-6 space-y-5">
            <%!-- Name --%>
            <div>
              <label class="text-xs font-medium opacity-60 mb-1.5 block">Name <span class="opacity-40">(optional)</span></label>
              <input
                type="text"
                name="title"
                placeholder="e.g. Refactor auth module"
                class="input input-bordered w-full bg-base-200/50 text-sm falcon-input"
              />
            </div>

            <%!-- Model Selector --%>
            <div>
              <label class="text-xs font-medium opacity-60 mb-1.5 block">Model</label>
              <select name="model" class="select select-bordered w-full bg-base-200/50 falcon-input">
                <option :for={model <- @models} value={"#{model.provider_id}::#{model.id}"}>
                  {model.name} ({model.provider_name})
                </option>
                <option :if={@models == []} value="llama3.1:8b">llama3.1:8b (default)</option>
              </select>
            </div>

            <%!-- System Prompt --%>
            <div>
              <label class="text-xs font-medium opacity-60 mb-1.5 block">System Prompt</label>
              <textarea
                name="system_prompt"
                class="textarea textarea-bordered w-full h-24 bg-base-200/50 text-sm falcon-input resize-none"
                placeholder="You are a helpful assistant..."
              ></textarea>
            </div>

            <%!-- Scoped Paths --%>
            <div>
              <label class="text-xs font-medium opacity-60 mb-1.5 flex items-center gap-1.5">
                <.icon name="hero-folder" class="size-3.5 text-secondary" /> Scoped Paths
              </label>
              <textarea
                name="scoped_paths"
                class="textarea textarea-bordered w-full h-20 bg-base-200/50 font-mono text-xs falcon-input resize-none"
                placeholder="/home/matt/Code/my-project&#10;/home/matt/Code/another-repo"
              ></textarea>
              <p class="text-[10px] opacity-30 mt-1.5 flex items-center gap-1">
                <.icon name="hero-shield-check-micro" class="size-3" />
                Enables sandboxed file/command tools within these directories
              </p>
            </div>

            <%!-- Advanced Settings --%>
            <details class="group">
              <summary class="flex items-center gap-2 cursor-pointer text-xs font-medium opacity-40 hover:opacity-60 transition-opacity">
                <.icon name="hero-adjustments-horizontal-micro" class="size-3.5" />
                Advanced Parameters
                <.icon
                  name="hero-chevron-right-micro"
                  class="size-3 transition-transform group-open:rotate-90"
                />
              </summary>
              <div class="mt-3 grid grid-cols-3 gap-3">
                <div>
                  <label class="text-[10px] opacity-40 mb-1 block">Temperature</label>
                  <input
                    type="number"
                    name="temperature"
                    class="input input-bordered input-sm w-full bg-base-200/50 text-xs falcon-input"
                    min="0"
                    max="2"
                    step="0.1"
                    placeholder="0.7"
                  />
                </div>
                <div>
                  <label class="text-[10px] opacity-40 mb-1 block">Max Tokens</label>
                  <input
                    type="number"
                    name="max_tokens"
                    class="input input-bordered input-sm w-full bg-base-200/50 text-xs falcon-input"
                    placeholder="4096"
                  />
                </div>
                <div>
                  <label class="text-[10px] opacity-40 mb-1 block">Top P</label>
                  <input
                    type="number"
                    name="top_p"
                    class="input input-bordered input-sm w-full bg-base-200/50 text-xs falcon-input"
                    min="0"
                    max="1"
                    step="0.05"
                    placeholder="0.9"
                  />
                </div>
              </div>
            </details>

            <%!-- Modal Actions --%>
            <div class="flex justify-end gap-3 pt-2">
              <button type="button" class="btn btn-ghost btn-sm" phx-click="close_modal">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary btn-sm gap-1.5 shadow-lg shadow-primary/20">
                <.icon name="hero-sparkles-micro" class="size-4" /> Create Chat
              </button>
            </div>
          </form>
        </div>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  # --- Helpers ---

  defp load_models do
    Falcon.LLM.ProviderRegistry.list_all_models()
  end

  defp parse_model_selection(nil), do: {nil, "llama3.1:8b"}

  defp parse_model_selection(value) do
    # Format is "provider_uuid::model_id" (double colon separator)
    case String.split(value, "::", parts: 2) do
      [provider_id, model_id] -> {provider_id, model_id}
      [model_id] -> {nil, model_id}
    end
  end

  defp parse_paths(nil), do: []
  defp parse_paths(""), do: []

  defp parse_paths(paths_str) do
    paths_str
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_tools(nil), do: []
  defp parse_tools(""), do: []

  defp parse_tools(tools_str) do
    tools_str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp parse_parameters(params) do
    %{}
    |> maybe_put_float("temperature", params["temperature"])
    |> maybe_put_int("max_tokens", params["max_tokens"])
    |> maybe_put_float("top_p", params["top_p"])
  end

  defp maybe_put_float(map, _key, nil), do: map
  defp maybe_put_float(map, _key, ""), do: map

  defp maybe_put_float(map, key, val) do
    case Float.parse(val) do
      {f, _} -> Map.put(map, key, f)
      :error -> map
    end
  end

  defp maybe_put_int(map, _key, nil), do: map
  defp maybe_put_int(map, _key, ""), do: map

  defp maybe_put_int(map, key, val) do
    case Integer.parse(val) do
      {i, _} -> Map.put(map, key, i)
      :error -> map
    end
  end

  defp render_markdown(nil), do: ""
  defp render_markdown(""), do: ""

  defp render_markdown(text) do
    text
    |> escape_html()
    |> then(&Regex.replace(~r/```(\w*)\n(.*?)```/s, &1, fn _, lang, code ->
      "<pre><code class=\"language-#{lang}\">#{code}</code></pre>"
    end))
    |> String.replace(~r/`([^`]+)`/, "<code>\\1</code>")
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\*(.+?)\*/, "<em>\\1</em>")
    |> String.replace("\n", "<br/>")
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
