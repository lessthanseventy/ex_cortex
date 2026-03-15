defmodule ExCortexWeb.WonderLive do
  @moduledoc "Pure LLM chat — no data grounding."
  use ExCortexWeb, :live_view

  alias ExCortex.Muse
  alias ExCortex.Thoughts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Wonder",
       messages: [],
       input: "",
       loading: false
     )}
  end

  @impl true
  def handle_event("ask", %{"question" => question}, socket) when question != "" do
    socket = assign(socket, loading: true, input: "")
    messages = socket.assigns.messages ++ [%{role: "user", content: question}]
    socket = assign(socket, messages: messages)

    Task.async(fn -> Muse.ask(question, scope: "wonder") end)
    {:noreply, socket}
  end

  def handle_event("ask", _, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"question" => value}, socket) do
    {:noreply, assign(socket, input: value)}
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
      <div class="flex-1 overflow-y-auto p-4 space-y-4" id="messages" phx-hook="ScrollBottom">
        <div :if={@messages == []} class="text-center text-zinc-500 mt-20">
          <p class="text-lg">What are you wondering about?</p>
          <p class="text-sm mt-2">Pure LLM chat — no data grounding.</p>
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
          <span class="animate-pulse">Thinking...</span>
        </div>
      </div>

      <form phx-submit="ask" class="border-t border-zinc-700 p-4">
        <div class="flex gap-2">
          <input
            type="text"
            name="question"
            value={@input}
            phx-change="update_input"
            placeholder="What are you wondering about?"
            aria-label="What are you wondering about"
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

  defp render_markdown(text), do: ExCortexWeb.Markdown.render(text)
end
