defmodule ExCortexWeb.SensesLive do
  @moduledoc "Source management — active senses, reflex library, expressions."
  use ExCortexWeb, :live_view

  import SaladUI.Badge

  alias ExCortex.Expressions
  alias ExCortex.Expressions.Expression
  alias ExCortex.Lobe
  alias ExCortex.Repo
  alias ExCortex.Ruminations
  alias ExCortex.Senses.Reflex
  alias ExCortex.Senses.Sense
  alias ExCortex.Senses.Supervisor, as: SensesSupervisor
  alias ExCortex.Senses.Worker

  # Declare atoms so String.to_existing_atom/1 works at runtime
  @valid_tabs [:active, :reflexes, :streams, :digests, :expressions]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "sources")
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "source_activity")
      :timer.send_interval(10_000, self(), :refresh)
    end

    {:ok,
     load_data(
       assign(socket,
         page_title: "Senses",
         tab: :active,
         expanding: nil,
         editing_sense: nil,
         expanded_panels: MapSet.new(),
         editing_expression: nil,
         expression_type_preview: "slack"
       )
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load_data(socket)}
  def handle_info(_msg, socket), do: {:noreply, load_data(socket)}

  defp load_data(socket) do
    import Ecto.Query

    senses = Repo.all(from(s in Sense, order_by: [desc: s.inserted_at]))
    installed_ids = MapSet.new(senses, & &1.reflex_id)

    reflexes = Enum.reject(Reflex.reflexes(), &MapSet.member?(installed_ids, &1.id))
    reflexes_by_lobe = group_by_lobe(reflexes)

    streams = Enum.reject(Reflex.streams(), &MapSet.member?(installed_ids, &1.id))
    streams_by_lobe = group_by_lobe(streams)

    digests = Enum.reject(Reflex.digests(), &MapSet.member?(installed_ids, &1.id))

    expressions = Expressions.list_expressions()

    assign(socket,
      senses: senses,
      reflexes: reflexes,
      reflexes_by_lobe: reflexes_by_lobe,
      feed_streams: streams,
      streams_by_lobe: streams_by_lobe,
      digests: digests,
      expressions: expressions
    )
  end

  defp sense_display_name(%Sense{name: name}) when is_binary(name) and name != "", do: name

  defp sense_display_name(%Sense{reflex_id: reflex_id}) when is_binary(reflex_id) do
    case Reflex.get(reflex_id) do
      nil -> reflex_id
      reflex -> reflex.name
    end
  end

  defp sense_display_name(%Sense{source_type: type}), do: String.capitalize(type) <> " source"

  defp format_time(nil), do: "never"
  defp format_time(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp status_color("active"), do: "green"
  defp status_color("paused"), do: "amber"
  defp status_color("error"), do: "red"
  defp status_color(_), do: "dim"

  defp broadcast_sources do
    Phoenix.PubSub.broadcast(ExCortex.PubSub, "sources", :refresh)
  end

  defp group_by_lobe(items) do
    lobe_order = %{frontal: 0, temporal: 1, parietal: 2, occipital: 3, limbic: 4, cerebellar: 5}

    items
    |> Enum.group_by(fn item -> item.lobe || :other end)
    |> Enum.sort_by(fn {lobe, _} -> Map.get(lobe_order, lobe, 99) end)
  end

  defp lobe_label(lobe), do: Lobe.label(lobe)

  defp config_display(value) when is_list(value), do: Enum.join(value, ", ")
  defp config_display(value), do: to_string(value)

  # ── Events ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    valid =
      if tab in Enum.map(@valid_tabs, &to_string/1),
        do: String.to_existing_atom(tab),
        else: :active

    {:noreply, assign(socket, tab: valid, expanding: nil)}
  end

  @impl true
  def handle_event("toggle_panel", %{"panel" => panel}, socket) do
    panels = socket.assigns.expanded_panels

    panels =
      if MapSet.member?(panels, panel),
        do: MapSet.delete(panels, panel),
        else: MapSet.put(panels, panel)

    {:noreply,
     socket
     |> assign(expanded_panels: panels)
     |> push_event("persist_toggles", %{expanded_panels: MapSet.to_list(panels)})}
  end

  @impl true
  def handle_event("restore_toggles", state, socket) do
    panels = state |> Map.get("expanded_panels", []) |> MapSet.new()
    {:noreply, assign(socket, expanded_panels: panels)}
  end

  @impl true
  def handle_event("toggle_sense", %{"id" => id}, socket) do
    expanding = if socket.assigns.expanding == id, do: nil, else: id
    {:noreply, assign(socket, expanding: expanding)}
  end

  @impl true
  def handle_event("activate_source", %{"id" => id}, socket) do
    case Repo.get(Sense, id) do
      nil ->
        {:noreply, socket}

      sense ->
        sense
        |> Sense.changeset(%{status: "active", error_message: nil})
        |> Repo.update!()

        SensesSupervisor.start_source(sense)
        broadcast_sources()
        {:noreply, load_data(socket)}
    end
  end

  @impl true
  def handle_event("pause_source", %{"id" => id}, socket) do
    case Repo.get(Sense, id) do
      nil ->
        {:noreply, socket}

      sense ->
        sense
        |> Sense.changeset(%{status: "paused"})
        |> Repo.update!()

        SensesSupervisor.stop_source(id)
        broadcast_sources()
        {:noreply, load_data(socket)}
    end
  end

  @impl true
  def handle_event("delete_source", %{"id" => id}, socket) do
    case Repo.get(Sense, id) do
      nil ->
        {:noreply, socket}

      sense ->
        SensesSupervisor.stop_source(id)
        Repo.delete!(sense)
        broadcast_sources()
        {:noreply, load_data(socket)}
    end
  end

  @impl true
  def handle_event("sync_source", %{"id" => id}, socket) do
    Worker.sync(id)
    {:noreply, put_flash(socket, :info, "Sync triggered.")}
  end

  @impl true
  def handle_event("sync_all", _params, socket) do
    active = Enum.filter(socket.assigns.senses, &(&1.status == "active"))
    Enum.each(active, &Worker.sync(&1.id))
    {:noreply, put_flash(socket, :info, "Syncing #{length(active)} active senses.")}
  end

  @impl true
  def handle_event("edit_sense", %{"id" => id}, socket) do
    editing = if socket.assigns.editing_sense == id, do: nil, else: id
    {:noreply, assign(socket, editing_sense: editing)}
  end

  @impl true
  def handle_event("save_sense", %{"_sense_id" => id} = params, socket) do
    case Repo.get(Sense, id) do
      nil ->
        {:noreply, socket}

      sense ->
        name = params["name"] || sense.name

        # Rebuild config from form params, preserving types
        new_config =
          params
          |> Map.drop(["_sense_id", "_csrf_token", "name"])
          |> Enum.reduce(sense.config, fn {key, value}, acc ->
            Map.put(acc, key, coerce_config_value(value, Map.get(sense.config, key)))
          end)

        sense
        |> Sense.changeset(%{name: name, config: new_config})
        |> Repo.update!()

        # Restart worker if active so it picks up new config
        if sense.status == "active" do
          SensesSupervisor.stop_source(id)
          SensesSupervisor.start_source(%{sense | name: name, config: new_config})
        end

        broadcast_sources()
        {:noreply, socket |> assign(editing_sense: nil) |> load_data()}
    end
  end

  @impl true
  def handle_event("navigate", %{"to" => path}, socket) do
    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_event("install_reflex", %{"reflex-id" => reflex_id}, socket) do
    reflex = Reflex.get(reflex_id)

    if reflex do
      case reflex.kind do
        :digest -> install_digest(reflex)
        _ -> install_sense(reflex)
      end

      broadcast_sources()
    end

    {:noreply, socket |> assign(tab: :active) |> load_data()}
  end

  @impl true
  def handle_event("preview_expression_type", %{"expression" => %{"type" => type}}, socket) do
    {:noreply, assign(socket, expression_type_preview: type)}
  end

  def handle_event("preview_expression_type", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("create_expression", %{"expression" => params}, socket) do
    config = build_expression_config(params)
    attrs = %{name: params["name"], type: params["type"], config: config}

    case Expressions.create_expression(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(expression_type_preview: "slack")
         |> put_flash(:info, "Expression created.")
         |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create expression.")}
    end
  end

  @impl true
  def handle_event("edit_expression", %{"id" => id}, socket) do
    editing = if socket.assigns.editing_expression == id, do: nil, else: id
    {:noreply, assign(socket, editing_expression: editing)}
  end

  @impl true
  def handle_event("save_expression", %{"expression" => params, "_expression_id" => id}, socket) do
    case Repo.get(Expression, String.to_integer(id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Expression not found.")}

      expr ->
        config = build_expression_config(Map.put(params, "type", expr.type))

        expr
        |> Expression.changeset(%{config: config})
        |> Repo.update()

        {:noreply, socket |> assign(editing_expression: nil) |> load_data()}
    end
  end

  @impl true
  def handle_event("delete_expression", %{"id" => id}, socket) do
    case Repo.get(Expression, String.to_integer(id)) do
      nil ->
        {:noreply, socket}

      expr ->
        Expressions.delete_expression(expr)
        {:noreply, socket |> put_flash(:info, "Expression deleted.") |> load_data()}
    end
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp install_sense(reflex) do
    %Sense{}
    |> Sense.changeset(%{
      source_type: reflex.source_type,
      config: reflex.default_config,
      reflex_id: reflex.id,
      status: "paused"
    })
    |> Repo.insert()
  end

  defp install_digest(reflex) do
    tmpl = reflex.rumination_template
    sources = get_in(reflex.default_config, ["sources"]) || []
    lobe = Lobe.get(reflex.lobe)
    lobe_iterations = if lobe, do: lobe.processing.max_tool_iterations, else: 15

    # Create feed senses for each source
    sense_ids =
      for %{"name" => name, "url" => url} <- sources do
        {:ok, sense} =
          %Sense{}
          |> Sense.changeset(%{
            name: name,
            source_type: "feed",
            config: %{"url" => url, "interval" => 1_800_000},
            reflex_id: reflex.id,
            status: "paused"
          })
          |> Repo.insert()

        to_string(sense.id)
      end

    # Create lobe-shaped pipeline: prepend steps + core digest steps + append steps
    pipeline = if lobe, do: lobe.pipeline, else: %{prepend_steps: [], append_steps: []}
    prepend = Map.get(pipeline, :prepend_steps, [])
    append = Map.get(pipeline, :append_steps, [])

    # Prepend steps from lobe
    prepend_synapses =
      for step_type <- prepend do
        step_def = Lobe.pipeline_step_def(step_type, tmpl.cluster, tmpl.gatherer)

        {:ok, s} =
          Ruminations.create_synapse(%{
            name: "#{reflex.name}: #{step_def.name_suffix}",
            description: step_def.description,
            trigger: "manual",
            output_type: step_def.output_type,
            cluster_name: step_def.cluster_name,
            loop_tools: Map.get(step_def, :loop_tools),
            max_tool_iterations: lobe_iterations,
            roster: step_def.roster
          })

        s
      end

    # Core digest steps
    {:ok, s1} =
      Ruminations.create_synapse(%{
        name: "#{reflex.name}: Gather",
        description:
          "Collect the latest items from the feed sources. For each item, extract: title, source, URL, and a 1-sentence summary. " <>
            "IMPORTANT: Always include the original URL for every item — these will be clickable links in the final output. " <>
            "NEVER invent or fabricate details — only report what the source material actually contains. No made-up CVE numbers, names, or statistics. " <>
            "Group items by subtopic. Discard duplicates and items older than #{tmpl.window}.",
        trigger: "manual",
        output_type: "freeform",
        cluster_name: tmpl.cluster,
        loop_tools: ["fetch_url", "web_search"],
        max_tool_iterations: lobe_iterations,
        roster: [%{"who" => "all", "preferred_who" => tmpl.gatherer, "how" => "solo", "when" => "sequential"}]
      })

    {:ok, s2} =
      Ruminations.create_synapse(%{
        name: "#{reflex.name}: Analyze",
        description:
          "Analyze the gathered items. Identify the top 5-10 most significant stories. " <>
            "For each, write a 2-3 sentence analysis explaining why it matters. " <>
            "Preserve the original source URLs — format each story as: **[Title](url)** — analysis. " <>
            "ONLY use facts from the gathered items. Do not add information from outside the provided content. " <>
            "If a detail (version number, CVE, statistic) isn't in the source, don't include it. " <>
            "End with a 'Trends' section noting any patterns across the stories.",
        trigger: "manual",
        output_type: "freeform",
        cluster_name: tmpl.cluster,
        roster: [%{"who" => "all", "preferred_who" => tmpl.analyst, "how" => "solo", "when" => "sequential"}]
      })

    slug = reflex.name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")

    {:ok, s3} =
      Ruminations.create_synapse(%{
        name: "#{reflex.name}: Publish",
        description:
          "Format the analysis as a concise dashboard signal card. Use markdown with clickable links. " <>
            "Structure: brief intro paragraph, then a bulleted list of top stories as **[Title](url)** — one-liner. " <>
            "Keep it scannable — this is a digest, not an essay.",
        trigger: "manual",
        output_type: "signal",
        cluster_name: tmpl.cluster,
        pin_slug: slug,
        pinned: true,
        roster: [%{"who" => "all", "preferred_who" => tmpl.analyst, "how" => "solo", "when" => "sequential"}]
      })

    # Append steps from lobe
    append_synapses =
      for step_type <- append do
        step_def = Lobe.pipeline_step_def(step_type, tmpl.cluster, tmpl.analyst)

        {:ok, s} =
          Ruminations.create_synapse(%{
            name: "#{reflex.name}: #{step_def.name_suffix}",
            description: step_def.description,
            trigger: "manual",
            output_type: step_def.output_type,
            cluster_name: step_def.cluster_name,
            loop_tools: Map.get(step_def, :loop_tools),
            roster: step_def.roster
          })

        s
      end

    all_synapses = prepend_synapses ++ [s1, s2, s3] ++ append_synapses

    steps =
      all_synapses
      |> Enum.with_index(1)
      |> Enum.map(fn {s, order} -> %{"step_id" => s.id, "order" => order} end)

    Ruminations.create_rumination(%{
      name: reflex.name,
      description: tmpl.description,
      trigger: "scheduled",
      schedule: tmpl.schedule,
      source_ids: sense_ids,
      status: "paused",
      steps: steps
    })
  end

  # Coerce string form values back to their original types
  defp coerce_config_value(value, original) when is_integer(original) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> value
    end
  end

  defp coerce_config_value(value, original) when is_boolean(original), do: value in ["true", "1"]

  defp coerce_config_value(value, original) when is_list(original) do
    value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp coerce_config_value(value, _original), do: value

  defp build_expression_config(%{"type" => "slack"} = p), do: %{"webhook_url" => p["webhook_url"] || ""}
  defp build_expression_config(%{"type" => "webhook"} = p), do: %{"url" => p["url"] || "", "headers" => %{}}

  defp build_expression_config(%{"type" => type} = p) when type in ["github_issue", "github_pr"],
    do: %{
      "token" => p["token"] || "",
      "owner" => p["owner"] || "",
      "repo" => p["repo"] || "",
      "base_branch" => p["base_branch"] || "",
      "file_path" => p["file_path"] || ""
    }

  defp build_expression_config(%{"type" => "email"} = p),
    do: %{"api_key" => p["api_key"] || "", "from" => p["from"] || "", "to" => p["to"] || ""}

  defp build_expression_config(%{"type" => "pagerduty"} = p),
    do: %{"routing_key" => p["routing_key"] || "", "severity" => p["severity"] || "error"}

  defp build_expression_config(_), do: %{}

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div id="senses-root" class="space-y-6" phx-hook="PersistToggles" data-page="senses">
      <%!-- Header panel --%>
      <.panel title="SENSES">
        <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p class="t-muted text-sm">
              Manage active data feeds, configure reflexes, streams, and expressions.
            </p>
            <p class="t-dim text-xs mt-0.5">
              {length(@senses)} sense{if length(@senses) != 1, do: "s"} · {Enum.count(
                @senses,
                &(&1.status == "active")
              )} active · {length(@expressions)} expression{if length(@expressions) != 1, do: "s"}
            </p>
          </div>
          <.key_hints hints={[
            {"A", "active"},
            {"R", "reflexes"},
            {"D", "digests"},
            {"S", "streams"},
            {"E", "expressions"}
          ]} />
        </div>
      </.panel>

      <%!-- Tab bar --%>
      <div class="flex gap-1 border-b border-border">
        <%= for {tab_id, label} <- [
          {:active, "Active"},
          {:reflexes, "Reflexes"},
          {:digests, "Digests"},
          {:streams, "Streams"},
          {:expressions, "Expressions"}
        ] do %>
          <button
            type="button"
            phx-click="switch_tab"
            phx-value-tab={tab_id}
            class={[
              "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors",
              if(@tab == tab_id,
                do: "border-primary text-foreground",
                else: "border-transparent text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            {label}
          </button>
        <% end %>
      </div>

      <%!-- Active senses --%>
      <%= if @tab == :active do %>
        <%= if @senses == [] do %>
          <.panel title="NO SENSES">
            <p class="t-muted text-sm">
              No senses installed. Browse the
              <button
                type="button"
                phx-click="switch_tab"
                phx-value-tab="reflexes"
                class="underline hover:no-underline"
              >
                Reflexes
              </button>
              tab to add one.
            </p>
          </.panel>
        <% else %>
          <% active_senses = Enum.filter(@senses, &(&1.status == "active")) %>
          <% inactive_senses = Enum.reject(@senses, &(&1.status == "active")) %>

          <.panel title={"ACTIVE (#{length(active_senses)})"}>
            <div class="flex justify-end mb-2">
              <.button
                type="button"
                size="sm"
                variant="outline"
                phx-click="sync_all"
              >
                Sync All
              </.button>
            </div>
            <div class="space-y-2">
              <.sense_row
                :for={sense <- active_senses}
                sense={sense}
                expanding={@expanding}
                editing={@editing_sense}
                display_name={sense_display_name(sense)}
              />
            </div>
          </.panel>

          <%= if inactive_senses != [] do %>
            <.panel title={"PAUSED (#{length(inactive_senses)})"}>
              <div class="space-y-2">
                <.sense_row
                  :for={sense <- inactive_senses}
                  sense={sense}
                  expanding={@expanding}
                  editing={@editing_sense}
                  display_name={sense_display_name(sense)}
                />
              </div>
            </.panel>
          <% end %>
        <% end %>
      <% end %>

      <%!-- Reflex library, grouped by category --%>
      <%= if @tab == :reflexes do %>
        <p class="t-muted text-sm mb-2">
          Pre-built source templates. Install a reflex to add a sense — configure and activate it from the Active tab.
        </p>
        <%= if @reflexes == [] do %>
          <.panel title="REFLEX LIBRARY">
            <p class="t-dim text-xs">All reflexes are installed.</p>
          </.panel>
        <% else %>
          <%= for {lobe, items} <- @reflexes_by_lobe do %>
            <.panel
              title={"#{String.upcase(lobe_label(lobe))} (#{length(items)})"}
              on_toggle="toggle_panel"
              toggle_value={"reflex-#{lobe}"}
              collapsed={not MapSet.member?(@expanded_panels, "reflex-#{lobe}")}
              summary={"#{length(items)} reflexes"}
            >
              <div class="space-y-2">
                <.reflex_row :for={reflex <- items} reflex={reflex} />
              </div>
            </.panel>
          <% end %>
        <% end %>
      <% end %>

      <%!-- Expressions --%>
      <%= if @tab == :expressions do %>
        <div class="space-y-4">
          <.panel title={"EXPRESSIONS (#{length(@expressions)})"}>
            <p class="t-muted text-sm mb-4">
              Named delivery integrations used by thoughts to send results to Slack, GitHub, webhooks, email, or PagerDuty.
            </p>
            <%= if @expressions == [] do %>
              <p class="t-dim text-xs">No expressions configured. Add one below.</p>
            <% else %>
              <div class="space-y-2">
                <.expression_row
                  :for={expr <- @expressions}
                  expr={expr}
                  editing={@editing_expression}
                />
              </div>
            <% end %>
          </.panel>

          <.panel title="ADD EXPRESSION">
            <form
              phx-submit="create_expression"
              phx-change="preview_expression_type"
              class="space-y-3"
            >
              <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div>
                  <label class="text-xs t-muted uppercase tracking-wider">Name</label>
                  <input
                    type="text"
                    name="expression[name]"
                    placeholder="e.g. team-slack"
                    class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
                  />
                </div>
                <div>
                  <label class="text-xs t-muted uppercase tracking-wider">Type</label>
                  <select
                    name="expression[type]"
                    class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
                  >
                    <option value="slack">Slack</option>
                    <option value="webhook">Webhook</option>
                    <option value="github_issue">GitHub Issue</option>
                    <option value="github_pr">GitHub PR</option>
                    <option value="email">Email</option>
                    <option value="pagerduty">PagerDuty</option>
                  </select>
                </div>
              </div>
              <.expression_config_fields type={@expression_type_preview} expression={nil} />
              <div class="flex justify-end pt-1">
                <.button type="submit" size="sm">Add Expression</.button>
              </div>
            </form>
          </.panel>
        </div>
      <% end %>

      <%!-- Digests (compound sense + rumination) --%>
      <%= if @tab == :digests do %>
        <.panel title="DIGESTS">
          <p class="t-muted text-sm mb-4">
            Scheduled pipelines that gather, analyze, and summarize feeds into signal cards with links. Installing a digest creates the senses and rumination wired together.
          </p>
          <%= if @digests == [] do %>
            <p class="t-dim text-xs">All digests are installed.</p>
          <% else %>
            <div class="space-y-2">
              <.digest_row :for={digest <- @digests} reflex={digest} />
            </div>
          <% end %>
        </.panel>
      <% end %>

      <%!-- Streams (pre-configured RSS feeds), grouped by category --%>
      <%= if @tab == :streams do %>
        <%= if @feed_streams == [] do %>
          <.panel title="STREAMS">
            <p class="t-dim text-xs">All streams are installed.</p>
          </.panel>
        <% else %>
          <%= for {lobe, items} <- @streams_by_lobe do %>
            <.panel
              title={"#{String.upcase(lobe_label(lobe))} (#{length(items)})"}
              on_toggle="toggle_panel"
              toggle_value={"stream-#{lobe}"}
              collapsed={not MapSet.member?(@expanded_panels, "stream-#{lobe}")}
              summary={"#{length(items)} streams"}
            >
              <div class="space-y-2">
                <.reflex_row :for={feed <- items} reflex={feed} />
              </div>
            </.panel>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # ── Sub-components ────────────────────────────────────────────────────────

  attr :sense, Sense, required: true
  attr :expanding, :string, default: nil
  attr :editing, :string, default: nil
  attr :display_name, :string, required: true

  defp sense_row(assigns) do
    ~H"""
    <div class="rounded border overflow-hidden">
      <div
        class="flex items-center gap-3 px-3 py-2.5 cursor-pointer hover:bg-muted/20 transition-colors"
        phx-click="toggle_sense"
        phx-value-id={@sense.id}
      >
        <span class={[
          "transition-transform inline-block t-muted text-base leading-none shrink-0",
          if(@expanding == to_string(@sense.id), do: "rotate-90")
        ]}>
          ›
        </span>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="font-medium text-sm">{@display_name}</span>
            <.badge variant="outline" class="text-xs">{@sense.source_type}</.badge>
          </div>
          <p class="text-xs t-dim mt-0.5">
            last run: {format_time(@sense.last_run_at)}
            <span :if={@sense.error_message} class="t-red ml-1">{@sense.error_message}</span>
          </p>
        </div>
        <.status color={status_color(@sense.status)} label={@sense.status} />
      </div>

      <%= if @expanding == to_string(@sense.id) do %>
        <div class="border-t bg-muted/20 px-3 py-3">
          <div class="flex items-center gap-2 flex-wrap">
            <%= if @sense.status in ["paused", "error"] do %>
              <.button
                type="button"
                size="sm"
                phx-click="activate_source"
                phx-value-id={@sense.id}
              >
                Activate
              </.button>
            <% end %>
            <%= if @sense.status == "active" do %>
              <.button
                type="button"
                size="sm"
                variant="outline"
                phx-click="sync_source"
                phx-value-id={@sense.id}
              >
                Sync Now
              </.button>
              <.button
                type="button"
                size="sm"
                variant="outline"
                phx-click="pause_source"
                phx-value-id={@sense.id}
              >
                Pause
              </.button>
            <% end %>
            <.button
              type="button"
              size="sm"
              variant="destructive"
              phx-click="delete_source"
              phx-value-id={@sense.id}
              data-confirm={"Delete sense \"#{@display_name}\"?"}
              class="ml-auto"
            >
              Delete
            </.button>
          </div>

          <%= if @editing == to_string(@sense.id) do %>
            <form phx-submit="save_sense" class="mt-3 space-y-2">
              <input type="hidden" name="_sense_id" value={@sense.id} />
              <p class="text-xs t-muted uppercase tracking-wider font-semibold mb-1">Edit Config</p>
              <div class="flex gap-2 items-center">
                <label class="text-xs t-dim w-32 shrink-0 font-mono">name</label>
                <input
                  type="text"
                  name="name"
                  value={@sense.name}
                  class="flex-1 h-7 text-xs font-mono border border-input rounded px-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                />
              </div>
              <div
                :for={{k, v} <- Enum.sort(@sense.config)}
                class="flex gap-2 items-center"
              >
                <label class="text-xs t-dim w-32 shrink-0 font-mono">{k}</label>
                <input
                  type="text"
                  name={k}
                  value={config_display(v)}
                  class="flex-1 h-7 text-xs font-mono border border-input rounded px-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                />
              </div>
              <div class="flex gap-2 pt-1">
                <.button type="submit" size="sm">Save</.button>
                <.button
                  type="button"
                  size="sm"
                  variant="outline"
                  phx-click="edit_sense"
                  phx-value-id={@sense.id}
                >
                  Cancel
                </.button>
              </div>
            </form>
          <% else %>
            <div :if={@sense.config != %{}} class="mt-3 space-y-1">
              <div class="flex items-center justify-between mb-1">
                <p class="text-xs t-muted uppercase tracking-wider font-semibold">Config</p>
                <button
                  type="button"
                  phx-click="edit_sense"
                  phx-value-id={@sense.id}
                  class="text-xs t-dim hover:t-bright"
                >
                  edit
                </button>
              </div>
              <div
                :for={{k, v} <- Enum.sort(@sense.config)}
                class="flex gap-2 text-xs font-mono"
              >
                <span class="t-dim w-32 shrink-0 truncate">{k}</span>
                <span class="t-muted truncate">{config_display(v)}</span>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :reflex, Reflex, required: true

  defp reflex_row(assigns) do
    ~H"""
    <div class="rounded border p-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div class="space-y-0.5 min-w-0 flex-1">
        <div class="flex items-center gap-2 flex-wrap">
          <span class="font-medium text-sm">{@reflex.name}</span>
          <.badge variant="outline" class="text-xs">{@reflex.source_type}</.badge>
          <.badge :if={@reflex.suggested_cluster} variant="secondary" class="text-xs">
            {@reflex.suggested_cluster}
          </.badge>
        </div>
        <p class="text-xs t-muted">{@reflex.description}</p>
      </div>
      <.button
        type="button"
        size="sm"
        variant="outline"
        phx-click="install_reflex"
        phx-value-reflex-id={@reflex.id}
        class="shrink-0 self-start sm:self-auto"
      >
        Install
      </.button>
    </div>
    """
  end

  attr :reflex, Reflex, required: true

  defp digest_row(assigns) do
    sources = get_in(assigns.reflex.default_config, ["sources"]) || []
    tmpl = assigns.reflex.rumination_template || %{}

    assigns =
      assigns
      |> assign(:source_names, Enum.map(sources, & &1["name"]))
      |> assign(:schedule, Map.get(tmpl, :schedule, ""))
      |> assign(:cluster, Map.get(tmpl, :cluster, ""))

    ~H"""
    <div class="rounded border p-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div class="space-y-1 min-w-0 flex-1">
        <div class="flex items-center gap-2 flex-wrap">
          <span class="font-medium text-sm">{@reflex.name}</span>
          <.badge variant="outline" class="text-xs">digest</.badge>
          <.badge :if={@cluster != ""} variant="secondary" class="text-xs">{@cluster}</.badge>
        </div>
        <p class="text-xs t-muted">{@reflex.description}</p>
        <div class="flex flex-wrap gap-1.5 mt-1">
          <.badge :for={name <- @source_names} variant="outline" class="text-xs t-dim">{name}</.badge>
        </div>
        <p :if={@schedule != ""} class="text-xs t-dim mt-0.5">
          Schedule: <code class="text-xs">{@schedule}</code>
        </p>
      </div>
      <.button
        type="button"
        size="sm"
        variant="outline"
        phx-click="install_reflex"
        phx-value-reflex-id={@reflex.id}
        class="shrink-0 self-start sm:self-auto"
      >
        Install
      </.button>
    </div>
    """
  end

  attr :expr, Expression, required: true
  attr :editing, :string, default: nil

  defp expression_row(assigns) do
    ~H"""
    <div class="rounded border overflow-hidden">
      <div
        class="flex items-center gap-3 px-3 py-2.5 cursor-pointer hover:bg-muted/20 transition-colors"
        phx-click="edit_expression"
        phx-value-id={@expr.id}
      >
        <span class={[
          "transition-transform inline-block t-muted text-base leading-none shrink-0",
          if(@editing == to_string(@expr.id), do: "rotate-90")
        ]}>
          ›
        </span>
        <div class="flex-1 flex items-center gap-2 flex-wrap min-w-0">
          <span class="font-medium text-sm">{@expr.name}</span>
          <.badge variant="secondary" class="text-xs">{@expr.type}</.badge>
          <.badge
            :if={@expr.config == %{} or Enum.all?(@expr.config, fn {_, v} -> v == "" end)}
            variant="destructive"
            class="text-xs"
          >
            needs config
          </.badge>
        </div>
      </div>

      <%= if @editing == to_string(@expr.id) do %>
        <div class="border-t bg-muted/20 px-3 py-3">
          <form id={"expression-form-#{@expr.id}"} phx-submit="save_expression" class="space-y-3">
            <input type="hidden" name="_expression_id" value={@expr.id} />
            <.expression_config_fields type={@expr.type} expression={@expr} />
            <div class="flex items-center gap-2 pt-1">
              <.button type="submit" size="sm">Save</.button>
              <.button
                type="button"
                size="sm"
                variant="destructive"
                phx-click="delete_expression"
                phx-value-id={@expr.id}
                data-confirm={"Delete expression \"#{@expr.name}\"?"}
              >
                Delete
              </.button>
            </div>
          </form>
        </div>
      <% end %>
    </div>
    """
  end

  attr :type, :string, required: true
  attr :expression, :any, default: nil

  defp expression_config_fields(%{type: "slack"} = assigns) do
    ~H"""
    <div>
      <label class="text-xs t-muted uppercase tracking-wider">Webhook URL</label>
      <input
        type="text"
        name="expression[webhook_url]"
        value={@expression && @expression.config["webhook_url"]}
        placeholder="https://hooks.slack.com/..."
        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
      />
    </div>
    """
  end

  defp expression_config_fields(%{type: "webhook"} = assigns) do
    ~H"""
    <div>
      <label class="text-xs t-muted uppercase tracking-wider">URL</label>
      <input
        type="text"
        name="expression[url]"
        value={@expression && @expression.config["url"]}
        placeholder="https://..."
        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
      />
    </div>
    """
  end

  defp expression_config_fields(%{type: type} = assigns) when type in ["github_issue", "github_pr"] do
    ~H"""
    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <div>
        <label class="text-xs t-muted uppercase tracking-wider">Token</label>
        <input
          type="text"
          name="expression[token]"
          value={@expression && @expression.config["token"]}
          placeholder="ghp_..."
          class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
        />
      </div>
      <div>
        <label class="text-xs t-muted uppercase tracking-wider">Owner</label>
        <input
          type="text"
          name="expression[owner]"
          value={@expression && @expression.config["owner"]}
          placeholder="org-or-user"
          class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
        />
      </div>
      <div>
        <label class="text-xs t-muted uppercase tracking-wider">Repo</label>
        <input
          type="text"
          name="expression[repo]"
          value={@expression && @expression.config["repo"]}
          placeholder="repo-name"
          class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
        />
      </div>
      <div :if={@type == "github_pr"}>
        <label class="text-xs t-muted uppercase tracking-wider">Base Branch</label>
        <input
          type="text"
          name="expression[base_branch]"
          value={@expression && @expression.config["base_branch"]}
          placeholder="main"
          class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
        />
      </div>
    </div>
    """
  end

  defp expression_config_fields(%{type: "email"} = assigns) do
    ~H"""
    <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
      <div>
        <label class="text-xs t-muted uppercase tracking-wider">API Key</label>
        <input
          type="text"
          name="expression[api_key]"
          value={@expression && @expression.config["api_key"]}
          placeholder="sg_..."
          class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
        />
      </div>
      <div>
        <label class="text-xs t-muted uppercase tracking-wider">From</label>
        <input
          type="text"
          name="expression[from]"
          value={@expression && @expression.config["from"]}
          placeholder="from@example.com"
          class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
        />
      </div>
      <div>
        <label class="text-xs t-muted uppercase tracking-wider">To</label>
        <input
          type="text"
          name="expression[to]"
          value={@expression && @expression.config["to"]}
          placeholder="to@example.com"
          class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
        />
      </div>
    </div>
    """
  end

  defp expression_config_fields(%{type: "pagerduty"} = assigns) do
    ~H"""
    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <div>
        <label class="text-xs t-muted uppercase tracking-wider">Routing Key</label>
        <input
          type="text"
          name="expression[routing_key]"
          value={@expression && @expression.config["routing_key"]}
          placeholder="R..."
          class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
        />
      </div>
      <div>
        <label class="text-xs t-muted uppercase tracking-wider">Severity</label>
        <select
          name="expression[severity]"
          class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background mt-1 focus:outline-none focus:ring-1 focus:ring-ring"
        >
          <option
            :for={sev <- ~w(critical error warning info)}
            value={sev}
            selected={@expression && @expression.config["severity"] == sev}
          >
            {sev}
          </option>
        </select>
      </div>
    </div>
    """
  end

  defp expression_config_fields(assigns) do
    ~H"""
    <p class="text-xs t-dim">No additional configuration required.</p>
    """
  end
end
