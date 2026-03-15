defmodule ExCortexWeb.ThoughtsLive do
  @moduledoc "Saved thought templates — browse, edit, re-run."
  use ExCortexWeb, :live_view

  alias ExCortex.Muse
  alias ExCortex.Thoughts

  @impl true
  def mount(_params, _session, socket) do
    thoughts = Thoughts.list_thoughts(status: "saved")

    {:ok,
     assign(socket,
       page_title: "Thoughts",
       thoughts: thoughts,
       selected: nil,
       rerunning: nil
     )}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    thought = Thoughts.get_thought!(String.to_integer(id))
    {:noreply, assign(socket, selected: thought)}
  end

  def handle_event("deselect", _, socket) do
    {:noreply, assign(socket, selected: nil)}
  end

  def handle_event("rerun", %{"id" => id}, socket) do
    thought = Thoughts.get_thought!(String.to_integer(id))
    socket = assign(socket, rerunning: thought.id)

    Task.async(fn ->
      Muse.ask(thought.question, scope: thought.scope, source_filters: thought.source_filters)
    end)

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    thought = Thoughts.get_thought!(String.to_integer(id))
    Thoughts.delete_thought(thought)
    thoughts = Thoughts.list_thoughts(status: "saved")
    {:noreply, assign(socket, thoughts: thoughts, selected: nil)}
  end

  def handle_event("save_to_memory", %{"id" => id}, socket) do
    thought = Thoughts.get_thought!(String.to_integer(id))
    Thoughts.save_to_memory(thought)
    {:noreply, put_flash(socket, :info, "Saved to memory")}
  end

  @impl true
  def handle_info({ref, {:ok, new_thought}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    Thoughts.update_thought(new_thought, %{status: "saved"})
    thoughts = Thoughts.list_thoughts(status: "saved")
    {:noreply, assign(socket, thoughts: thoughts, rerunning: nil, selected: new_thought)}
  end

  def handle_info({ref, {:error, _}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket |> assign(rerunning: nil) |> put_flash(:error, "Re-run failed")}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, rerunning: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-4">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-xl font-semibold text-zinc-100">Saved Thoughts</h1>
        <.link navigate="/muse" class="text-sm text-teal-400 hover:text-teal-300">
          New thought via Muse &rarr;
        </.link>
      </div>

      <div :if={@thoughts == []} class="text-center text-zinc-500 mt-20">
        <p class="text-lg">No saved thoughts yet.</p>
        <p class="text-sm mt-2">
          Start a conversation in <.link navigate="/muse" class="text-teal-400">Muse</.link>
          or <.link navigate="/wonder" class="text-teal-400">Wonder</.link>, then save interesting responses.
        </p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <%!-- List --%>
        <div class="lg:col-span-1 space-y-2">
          <div
            :for={thought <- @thoughts}
            phx-click="select"
            phx-value-id={thought.id}
            class={[
              "p-3 rounded-lg border cursor-pointer transition-colors",
              if(@selected && @selected.id == thought.id,
                do: "border-teal-500 bg-zinc-800",
                else: "border-zinc-700 hover:border-zinc-500 bg-zinc-900"
              )
            ]}
          >
            <p class="text-sm text-zinc-200 line-clamp-2">{thought.question}</p>
            <div class="flex items-center gap-2 mt-2">
              <span class="text-xs text-zinc-500">{thought.scope}</span>
              <span
                :for={tag <- thought.tags || []}
                class="text-xs bg-zinc-700 px-1.5 py-0.5 rounded text-zinc-400"
              >
                {tag}
              </span>
            </div>
          </div>
        </div>

        <%!-- Detail --%>
        <div :if={@selected} class="lg:col-span-2 bg-zinc-900 border border-zinc-700 rounded-lg p-4">
          <div class="flex items-start justify-between mb-4">
            <h2 class="text-zinc-200 font-medium">{@selected.question}</h2>
            <div class="flex items-center gap-2">
              <button
                phx-click="rerun"
                phx-value-id={@selected.id}
                disabled={@rerunning == @selected.id}
                class="text-xs text-teal-400 hover:text-teal-300 disabled:opacity-50"
              >
                {if @rerunning == @selected.id, do: "Running...", else: "Re-run"}
              </button>
              <button
                phx-click="save_to_memory"
                phx-value-id={@selected.id}
                class="text-xs text-zinc-400 hover:text-zinc-200"
              >
                Save to memory
              </button>
              <button
                phx-click="delete"
                phx-value-id={@selected.id}
                data-confirm="Delete this thought?"
                class="text-xs text-red-400 hover:text-red-300"
              >
                Delete
              </button>
            </div>
          </div>
          <div :if={@selected.answer} class="prose prose-invert prose-sm max-w-none">
            {Phoenix.HTML.raw(render_markdown(@selected.answer))}
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_markdown(text), do: ExCortexWeb.Markdown.render(text)
end
