defmodule ExCortexWeb.GenesisLive do
  @moduledoc "Synaptogenesis — describe what you want, birth a new thought pathway."
  use ExCortexWeb, :live_view

  alias ExCortex.Genesis

  @impl true
  def mount(_params, _session, socket) do
    models = Genesis.available_models()
    default = List.first(models)

    {:ok,
     assign(socket,
       page_title: "Synaptogenesis",
       description: "",
       selected_model: default && "#{default.provider}:#{default.model}",
       models: models,
       phase: :describe,
       loading: false,
       proposal: nil,
       error: nil,
       editing_step: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("genesis", %{"description" => desc}, socket) when desc != "" do
    [provider, model] = String.split(socket.assigns.selected_model, ":", parts: 2)
    parent = self()

    Task.start(fn ->
      result = Genesis.synthesize(desc, provider: provider, model: model)
      send(parent, {:genesis_result, result})
    end)

    {:noreply, assign(socket, loading: true, error: nil, description: desc)}
  end

  def handle_event("genesis", _params, socket), do: {:noreply, socket}

  def handle_event("select_model", %{"model" => model}, socket) do
    {:noreply, assign(socket, selected_model: model)}
  end

  def handle_event("accept", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "#{socket.assigns.proposal.name} created (paused)")
     |> push_navigate(to: ~p"/ruminations")}
  end

  def handle_event("refine", _params, socket) do
    {:noreply, assign(socket, phase: :refine)}
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, phase: :describe, proposal: nil, error: nil)}
  end

  def handle_event("remove_step", %{"index" => idx}, socket) do
    index = String.to_integer(idx)
    proposal = socket.assigns.proposal
    steps = List.delete_at(proposal.steps, index)
    {:noreply, assign(socket, proposal: %{proposal | steps: steps})}
  end

  def handle_event("move_step_up", %{"index" => idx}, socket) do
    index = String.to_integer(idx)

    if index > 0 do
      proposal = socket.assigns.proposal
      steps = swap(proposal.steps, index, index - 1)
      {:noreply, assign(socket, proposal: %{proposal | steps: steps})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("move_step_down", %{"index" => idx}, socket) do
    index = String.to_integer(idx)
    proposal = socket.assigns.proposal

    if index < length(proposal.steps) - 1 do
      steps = swap(proposal.steps, index, index + 1)
      {:noreply, assign(socket, proposal: %{proposal | steps: steps})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_refined", _params, socket) do
    proposal = socket.assigns.proposal

    case Genesis.create_pipeline(proposal) do
      {:ok, rumination} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{rumination.name} created (paused)")
         |> push_navigate(to: ~p"/ruminations")}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Failed to save: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:genesis_result, {:ok, rumination}}, socket) do
    proposal = %{
      id: rumination.id,
      name: rumination.name,
      description: rumination.description,
      steps: load_steps(rumination)
    }

    {:noreply, assign(socket, loading: false, phase: :review, proposal: proposal)}
  end

  def handle_info({:genesis_result, {:error, reason}}, socket) do
    {:noreply, assign(socket, loading: false, error: "Genesis failed: #{inspect(reason)}")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_steps(rumination) do
    rumination.steps
    |> Enum.sort_by(&(&1["order"] || 0))
    |> Enum.map(&step_entry_to_map/1)
  end

  defp step_entry_to_map(%{"step_id" => step_id}) do
    synapse = ExCortex.Ruminations.get_synapse!(step_id)
    synapse_to_step(synapse)
  end

  defp synapse_to_step(synapse) do
    %{
      name: synapse.name,
      description: synapse.description,
      cluster_name: synapse.cluster_name,
      output_type: synapse.output_type,
      preferred_neuron: preferred_neuron(synapse.roster)
    }
  end

  defp preferred_neuron([%{"preferred_who" => name} | _]), do: name
  defp preferred_neuron(_), do: nil

  defp swap(list, i, j) do
    list
    |> List.replace_at(i, Enum.at(list, j))
    |> List.replace_at(j, Enum.at(list, i))
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.panel title="SYNAPTOGENESIS">
        <p class="t-muted text-sm">
          Describe what you want in plain language. Synaptogenesis will design a pipeline of clusters and neurons to accomplish it.
        </p>
      </.panel>

      <.phase_content
        phase={@phase}
        description={@description}
        selected_model={@selected_model}
        models={@models}
        loading={@loading}
        proposal={@proposal}
        error={@error}
      />
    </div>
    """
  end

  # -- Phase components --

  attr :phase, :atom, required: true
  attr :description, :string, required: true
  attr :selected_model, :string, required: true
  attr :models, :list, required: true
  attr :loading, :boolean, required: true
  attr :proposal, :any, required: true
  attr :error, :any, required: true

  defp phase_content(%{phase: :describe} = assigns) do
    ~H"""
    <.panel title="DESCRIBE">
      <form phx-submit="genesis" class="space-y-4">
        <textarea
          name="description"
          rows="4"
          value={@description}
          placeholder="e.g. Research the latest Elixir 1.19 features, summarize them, and post a briefing card to the dashboard"
          aria-label="Pipeline description"
          class="w-full bg-muted border border-border rounded px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-foreground"
          disabled={@loading}
        />

        <div class="flex items-center gap-3">
          <select
            name="model"
            aria-label="Model selector"
            phx-change="select_model"
            class="bg-muted border border-border rounded px-3 py-2 text-sm text-foreground"
          >
            <%= for m <- @models do %>
              <option
                value={"#{m.provider}:#{m.model}"}
                selected={@selected_model == "#{m.provider}:#{m.model}"}
              >
                {m.label}
              </option>
            <% end %>
          </select>

          <button
            type="submit"
            class="px-6 py-2 text-sm font-medium rounded bg-primary text-primary-foreground hover:opacity-90 disabled:opacity-50"
            disabled={@loading}
          >
            {if @loading, do: "Synthesizing...", else: "Synthesize"}
          </button>
        </div>
      </form>

      <.error_display error={@error} />
    </.panel>
    """
  end

  defp phase_content(%{phase: :review} = assigns) do
    ~H"""
    <.panel title="PROPOSED PIPELINE">
      <div class="space-y-4">
        <div>
          <h2 class="text-lg font-semibold t-bright">{@proposal.name}</h2>
          <p class="text-sm t-dim mt-1">{@proposal.description}</p>
        </div>

        <.step_chain steps={@proposal.steps} editable={false} />

        <div class="flex gap-2 pt-2">
          <button
            phx-click="accept"
            class="px-6 py-2 text-sm font-medium rounded bg-primary text-primary-foreground hover:opacity-90"
          >
            Accept
          </button>
          <button
            phx-click="refine"
            class="px-6 py-2 text-sm font-medium rounded border border-border text-foreground hover:bg-muted"
          >
            Refine
          </button>
          <button
            phx-click="back"
            class="px-4 py-2 text-sm t-dim hover:t-bright"
          >
            Start over
          </button>
        </div>
      </div>
    </.panel>
    """
  end

  defp phase_content(%{phase: :refine} = assigns) do
    ~H"""
    <.panel title="REFINE PIPELINE">
      <div class="space-y-4">
        <div>
          <h2 class="text-lg font-semibold t-bright">{@proposal.name}</h2>
          <p class="text-sm t-dim mt-1">{@proposal.description}</p>
        </div>

        <.step_chain steps={@proposal.steps} editable={true} />

        <div class="flex gap-2 pt-2">
          <button
            phx-click="save_refined"
            class="px-6 py-2 text-sm font-medium rounded bg-primary text-primary-foreground hover:opacity-90"
          >
            Save Pipeline
          </button>
          <button
            phx-click="back"
            class="px-4 py-2 text-sm t-dim hover:t-bright"
          >
            Start over
          </button>
        </div>

        <.error_display error={@error} />
      </div>
    </.panel>
    """
  end

  # -- Step chain display --

  attr :steps, :list, required: true
  attr :editable, :boolean, required: true

  defp step_chain(assigns) do
    ~H"""
    <div class="space-y-2">
      <.step_row :for={{step, idx} <- Enum.with_index(@steps)} step={step} index={idx} editable={@editable} last={idx == length(@steps) - 1} />
    </div>
    """
  end

  attr :step, :map, required: true
  attr :index, :integer, required: true
  attr :editable, :boolean, required: true
  attr :last, :boolean, required: true

  defp step_row(%{editable: true} = assigns) do
    ~H"""
    <div class="flex items-start gap-3 border border-border rounded p-3 bg-muted/20">
      <div class="flex flex-col gap-1 text-xs t-dim">
        <button :if={@index > 0} phx-click="move_step_up" phx-value-index={@index} class="hover:t-bright">↑</button>
        <span class="t-amber font-mono">{@index + 1}</span>
        <button :if={!@last} phx-click="move_step_down" phx-value-index={@index} class="hover:t-bright">↓</button>
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="font-medium text-sm">{@step.name}</span>
          <span class="text-xs t-dim px-1.5 py-0.5 rounded bg-muted">{@step.output_type}</span>
        </div>
        <p class="text-xs t-dim mt-0.5">{@step.description}</p>
        <div class="flex gap-3 text-xs t-dim mt-1">
          <span>cluster: {@step.cluster_name}</span>
          <span :if={@step.preferred_neuron}>neuron: {@step.preferred_neuron}</span>
        </div>
      </div>
      <button phx-click="remove_step" phx-value-index={@index} class="text-xs t-dim hover:text-destructive shrink-0">
        remove
      </button>
    </div>
    <.step_arrow :if={!@last} />
    """
  end

  defp step_row(assigns) do
    ~H"""
    <div class="flex items-start gap-3 border border-border rounded p-3">
      <span class="t-amber font-mono text-xs mt-0.5">{@index + 1}</span>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="font-medium text-sm">{@step.name}</span>
          <span class="text-xs t-dim px-1.5 py-0.5 rounded bg-muted">{@step.output_type}</span>
        </div>
        <p class="text-xs t-dim mt-0.5">{@step.description}</p>
        <div class="flex gap-3 text-xs t-dim mt-1">
          <span>cluster: {@step.cluster_name}</span>
          <span :if={@step.preferred_neuron}>neuron: {@step.preferred_neuron}</span>
        </div>
      </div>
    </div>
    <.step_arrow :if={!@last} />
    """
  end

  defp step_arrow(assigns) do
    ~H"""
    <div class="flex justify-center text-xs t-dim">↓</div>
    """
  end

  # -- Error display --

  attr :error, :any, required: true

  defp error_display(%{error: nil} = assigns), do: ~H""

  defp error_display(assigns) do
    ~H"""
    <div class="mt-3 p-3 rounded border border-red-500/30 bg-red-500/10 text-sm text-red-400">
      {@error}
    </div>
    """
  end
end
