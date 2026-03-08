defmodule ExCellenceServerWeb.EvaluateLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import ExCellenceDashboard.Components.ConsensusViz
  import ExCellenceDashboard.Components.VerdictPanel
  import SaladUI.Card

  alias Excellence.LLM.Ollama
  alias Excellence.Orchestrator

  @templates %{
    "content_moderation" => Excellence.Templates.ContentModeration,
    "code_review" => Excellence.Templates.CodeReview,
    "risk_assessment" => Excellence.Templates.RiskAssessment
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCellenceServer.PubSub, "evaluation:results")
    end

    templates =
      Enum.map(@templates, fn {key, mod} ->
        meta = mod.metadata()
        {key, "#{meta.name} Guild"}
      end)

    {:ok,
     assign(socket,
       page_title: "Evaluate",
       templates: templates,
       selected_template: nil,
       input_text: "",
       running: false,
       verdicts: [],
       role_results: [],
       decision: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("select_template", %{"template" => key}, socket) do
    {:noreply, assign(socket, selected_template: key)}
  end

  @impl true
  def handle_event("update_input", %{"input" => text}, socket) do
    {:noreply, assign(socket, input_text: text)}
  end

  @impl true
  def handle_event("run", _params, socket) do
    template_key = socket.assigns.selected_template
    input_text = socket.assigns.input_text

    if template_key && input_text != "" do
      socket = assign(socket, running: true, verdicts: [], role_results: [], decision: nil, error: nil)
      pid = self()

      Task.start(fn ->
        run_evaluation(template_key, input_text, pid)
      end)

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Select a guild and enter input text")}
    end
  end

  @impl true
  def handle_info({:evaluation_complete, result}, socket) do
    case result do
      {:ok, {action, details}} ->
        {:noreply,
         assign(socket,
           running: false,
           verdicts: details[:verdicts] || [],
           role_results: details[:role_results] || [],
           decision: %{
             action: action,
             confidence: details[:confidence] || 0.0,
             escalated: details[:escalated] || false,
             guard_blocked: details[:guard_blocked] || false
           }
         )}

      {:error, reason} ->
        {:noreply, assign(socket, running: false, error: inspect(reason))}
    end
  end

  @impl true
  def handle_info({:verdict_received, verdict}, socket) do
    {:noreply, assign(socket, verdicts: socket.assigns.verdicts ++ [verdict])}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp run_evaluation(template_key, input_text, caller_pid) do
    template_mod = Map.fetch!(@templates, template_key)
    meta = template_mod.metadata()

    ollama_url = Application.get_env(:ex_cellence_server, :ollama_url, "http://127.0.0.1:11434")
    provider = Ollama.new(base_url: ollama_url)

    roles = build_roles_from_template(meta)
    actions_mod = build_actions_from_template(meta)

    result =
      try do
        {:ok,
         Orchestrator.evaluate(
           %{subject: input_text},
           %{},
           roles: roles,
           actions: actions_mod,
           strategy: meta.strategy,
           llm_provider: provider,
           guards: []
         )}
      rescue
        e -> {:error, e}
      end

    send(caller_pid, {:evaluation_complete, result})
  end

  defp build_roles_from_template(meta) do
    Enum.map(meta.roles, fn role_def ->
      mod_name = Module.concat([Excellence, Roles, Macro.camelize(role_def.name)])

      if !Code.ensure_loaded?(mod_name) do
        contents =
          quote do
            use Excellence.Role

            system_prompt(unquote(role_def.system_prompt))

            unquote_splicing(
              Enum.map(role_def.perspectives, fn p ->
                quote do
                  perspective(unquote(String.to_atom(p.name)),
                    model: unquote(p.model),
                    strategy: unquote(String.to_atom(p.strategy)),
                    name: unquote("#{role_def.name}.#{p.name}")
                  )
                end
              end)
            )

            def build_prompt(input, _context) do
              "Evaluate the following:\n\n#{inspect(input)}"
            end
          end

        Module.create(mod_name, contents, Macro.Env.location(__ENV__))
      end

      mod_name
    end)
  end

  defp build_actions_from_template(meta) do
    mod_name = Module.concat([Excellence, DynamicActions, :Template])

    if !Code.ensure_loaded?(mod_name) do
      action_defs =
        Enum.map(meta.actions, fn action ->
          quote do
            action(unquote(action))
          end
        end)

      contents =
        quote do
          use Excellence.Actions

          unquote_splicing(action_defs)
        end

      Module.create(mod_name, contents, Macro.Env.location(__ENV__))
    end

    mod_name
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Evaluate</h1>

      <.card>
        <.card_content class="pt-6 space-y-4">
          <div>
            <label class="text-sm font-medium">Guild</label>
            <div class="flex gap-2 mt-2">
              <%= for {key, name} <- @templates do %>
                <.button
                  variant={if @selected_template == key, do: "default", else: "outline"}
                  phx-click="select_template"
                  phx-value-template={key}
                >
                  {name}
                </.button>
              <% end %>
            </div>
          </div>

          <div>
            <label class="text-sm font-medium">Input</label>
            <textarea
              class="mt-2 w-full rounded-md border bg-background px-3 py-2 text-sm min-h-[120px]"
              phx-change="update_input"
              name="input"
              placeholder="Enter text to evaluate..."
            ><%= @input_text %></textarea>
          </div>

          <.button phx-click="run" disabled={@running}>
            {if @running, do: "Running...", else: "Run"}
          </.button>
        </.card_content>
      </.card>

      <%= if @error do %>
        <.card>
          <.card_content class="pt-6">
            <p class="text-destructive">{@error}</p>
          </.card_content>
        </.card>
      <% end %>

      <%= if @verdicts != [] do %>
        <.verdict_panel verdicts={@verdicts} />
      <% end %>

      <%= if @decision do %>
        <.consensus_viz role_results={@role_results} decision={@decision} />
      <% end %>
    </div>
    """
  end
end
