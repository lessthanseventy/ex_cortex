defmodule ExCortexWeb.MuseLive do
  @moduledoc "Data-grounded chat — RAG over engrams and axioms."
  use ExCortexWeb, :live_view

  alias ExCortex.Muse
  alias ExCortex.Thoughts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Muse",
       messages: [],
       input: "",
       loading: false,
       filters_open: false,
       tag_filter: ""
     )}
  end

  @impl true
  def handle_event("ask", %{"question" => question}, socket) when question != "" do
    source_filters = parse_filters(socket.assigns.tag_filter)
    socket = assign(socket, loading: true, input: "")
    messages = socket.assigns.messages ++ [%{role: "user", content: question}]
    socket = assign(socket, messages: messages)

    Task.async(fn -> Muse.ask(question, scope: "muse", source_filters: source_filters) end)
    {:noreply, socket}
  end

  def handle_event("ask", _, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"question" => value}, socket) do
    {:noreply, assign(socket, input: value)}
  end

  def handle_event("toggle_filters", _, socket) do
    {:noreply, assign(socket, filters_open: !socket.assigns.filters_open)}
  end

  def handle_event("update_filters", %{"tag_filter" => tag_filter}, socket) do
    {:noreply, assign(socket, tag_filter: tag_filter)}
  end

  def handle_event("save_to_memory", %{"id" => id}, socket) do
    thought = Thoughts.get_thought!(String.to_integer(id))
    Thoughts.save_to_memory(thought)
    {:noreply, put_flash(socket, :info, "Saved to memory")}
  end

  @impl true
  def handle_info({ref, {:ok, thought}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    messages =
      socket.assigns.messages ++ [%{role: "assistant", content: thought.answer, thought_id: thought.id}]

    {:noreply, assign(socket, messages: messages, loading: false)}
  end

  def handle_info({ref, {:error, _reason}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    messages =
      socket.assigns.messages ++ [%{role: "assistant", content: "Sorry, I couldn't process that request."}]

    {:noreply, assign(socket, messages: messages, loading: false)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-8rem)]">
      <%!-- Filter panel --%>
      <div class="border-b border-zinc-700">
        <button
          phx-click="toggle_filters"
          class="w-full px-4 py-2 text-left text-sm text-zinc-400 hover:text-zinc-200 flex items-center gap-2"
        >
          <span :if={!@filters_open}>&#9654;</span>
          <span :if={@filters_open}>&#9660;</span>
          Filters <span :if={@tag_filter != ""} class="text-teal-400 text-xs">({@tag_filter})</span>
        </button>
        <div :if={@filters_open} class="px-4 pb-3">
          <form phx-change="update_filters" class="flex gap-2 items-center">
            <label class="text-xs text-zinc-500">Tags:</label>
            <input
              type="text"
              name="tag_filter"
              value={@tag_filter}
              placeholder="comma-separated tags to filter by"
              class="flex-1 bg-zinc-900 border border-zinc-700 rounded px-3 py-1 text-sm text-zinc-100"
            />
          </form>
        </div>
      </div>

      <%!-- Messages --%>
      <div class="flex-1 overflow-y-auto p-4 space-y-4" id="messages" phx-hook="ScrollBottom">
        <div :if={@messages == []} class="text-center text-zinc-500 mt-20">
          <p class="text-lg">What are you musing about?</p>
          <p class="text-sm mt-2">Grounded in your data — searches engrams and axioms.</p>
        </div>
        <div
          :for={msg <- @messages}
          class={[
            "max-w-2xl rounded-lg px-4 py-3",
            if(msg.role == "user",
              do: "ml-auto bg-zinc-800 text-zinc-100",
              else: "bg-zinc-900 border border-zinc-700"
            )
          ]}
        >
          <div class="prose prose-invert prose-sm max-w-none">
            {Phoenix.HTML.raw(render_markdown(msg.content))}
          </div>
          <button
            :if={msg.role == "assistant" && Map.has_key?(msg, :thought_id)}
            phx-click="save_to_memory"
            phx-value-id={msg.thought_id}
            class="mt-2 text-xs text-zinc-500 hover:text-teal-400 transition-colors"
          >
            Save to memory
          </button>
        </div>
        <div :if={@loading} class="flex items-center gap-2 text-zinc-500">
          <span class="animate-pulse">Musing...</span>
        </div>
      </div>

      <%!-- Input --%>
      <form phx-submit="ask" class="border-t border-zinc-700 p-4">
        <div class="flex gap-2">
          <input
            type="text"
            name="question"
            value={@input}
            phx-change="update_input"
            placeholder="What are you musing about?"
            aria-label="What are you musing about"
            class="flex-1 bg-zinc-900 border border-zinc-700 rounded-lg px-4 py-2 text-zinc-100 focus:border-teal-500 focus:ring-1 focus:ring-teal-500"
            autocomplete="off"
            autofocus
          />
          <button
            type="submit"
            disabled={@loading}
            class="px-4 py-2 bg-teal-600 hover:bg-teal-500 text-white rounded-lg disabled:opacity-50"
          >
            Ask
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp parse_filters(""), do: []

  defp parse_filters(tags) do
    tags |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp render_markdown(text), do: ExCortexWeb.Markdown.render(text)
end
