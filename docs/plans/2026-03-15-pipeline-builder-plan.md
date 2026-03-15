# Pipeline Builder Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add a visual pipeline builder to `/ruminations` so users can compose, reorder, and configure rumination steps (synapses + rosters) without leaving the page.

**Architecture:** Extend `RuminationsLive` with an `editing` mode that replaces the right panel with a pipeline builder. Extract neuron resolution logic from `ImpulseRunner` into a shared module for live preview. All new UI uses TUI components with box-drawing characters.

**Tech Stack:** Phoenix LiveView, Ecto, existing TUI components, existing Ruminations context module.

**Design doc:** `docs/plans/2026-03-15-pipeline-builder-design.md`

---

### Task 0: Extract neuron resolution into shared module

The `ImpulseRunner.resolve_neurons/1` logic (lines 223-333) is private. We need it accessible from the LiveView for the "resolved neuron preview" feature.

**Files:**
- Create: `lib/ex_cortex/ruminations/roster_resolver.ex`
- Modify: `lib/ex_cortex/ruminations/impulse_runner.ex:223-333`
- Test: `test/ex_cortex/ruminations/roster_resolver_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_cortex/ruminations/roster_resolver_test.exs
defmodule ExCortex.Ruminations.RosterResolverTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Ruminations.RosterResolver
  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo

  describe "resolve/1" do
    test "resolves 'all' to all active role neurons" do
      insert_neuron("Agent A", "role", "active", %{"rank" => "apprentice"})
      insert_neuron("Agent B", "role", "active", %{"rank" => "master"})
      insert_neuron("Archived", "role", "archived", %{"rank" => "apprentice"})

      result = RosterResolver.resolve(%{"who" => "all"})
      names = Enum.map(result, & &1.name)

      assert "Agent A" in names
      assert "Agent B" in names
      refute "Archived" in names
    end

    test "resolves rank-based who" do
      insert_neuron("Junior", "role", "active", %{"rank" => "apprentice"})
      insert_neuron("Senior", "role", "active", %{"rank" => "master"})

      result = RosterResolver.resolve(%{"who" => "apprentice"})
      names = Enum.map(result, & &1.name)

      assert names == ["Junior"]
    end

    test "resolves team-based who" do
      insert_neuron("Dev1", "role", "active", %{"rank" => "apprentice", "team_name" => "Dev"}, "Dev")
      insert_neuron("Ops1", "role", "active", %{"rank" => "apprentice"}, "Ops")

      result = RosterResolver.resolve(%{"who" => "team:Dev"})
      names = Enum.map(result, & &1.name)

      assert names == ["Dev1"]
    end

    test "resolves claude tier to inline spec" do
      result = RosterResolver.resolve(%{"who" => "claude_haiku"})
      assert [%{provider: "claude", model: "claude_haiku"}] = result
    end

    test "resolves full roster entry list" do
      insert_neuron("Agent A", "role", "active", %{"rank" => "master"})

      result = RosterResolver.resolve_roster([
        %{"who" => "master", "when" => "sequential", "how" => "solo"}
      ])

      assert [%{neurons: [%{name: "Agent A"}], when: "sequential", how: "solo"}] = result
    end
  end

  defp insert_neuron(name, type, status, config, team \\ nil) do
    Repo.insert!(%Neuron{
      name: name,
      type: type,
      status: status,
      config: config,
      team: team,
      source: "db",
      version: 1
    })
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex/ruminations/roster_resolver_test.exs`
Expected: FAIL — module `RosterResolver` not found

**Step 3: Write RosterResolver module**

```elixir
# lib/ex_cortex/ruminations/roster_resolver.ex
defmodule ExCortex.Ruminations.RosterResolver do
  @moduledoc """
  Resolves roster patterns to concrete neuron specs.
  Extracted from ImpulseRunner for reuse in LiveView previews.
  """

  import Ecto.Query
  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo

  @rank_values ["apprentice", "journeyman", "master"]

  @doc """
  Resolve a single roster entry (map with "who" key) to a list of neuron specs.
  """
  def resolve(%{"preferred_who" => name, "who" => rank})
      when is_binary(name) and name != "" and rank in @rank_values do
    case from(m in Neuron,
           where:
             m.type == "role" and m.status == "active" and m.name == ^name and
               fragment("config->>'rank' = ?", ^rank)
         )
         |> Repo.all()
         |> Enum.map(&neuron_to_spec/1) do
      [] -> resolve(%{"who" => rank})
      neurons -> neurons
    end
  end

  def resolve(%{"preferred_who" => name} = step) when is_binary(name) and name != "" do
    case from(m in Neuron,
           where: m.type == "role" and m.status == "active" and m.name == ^name
         )
         |> Repo.all()
         |> Enum.map(&neuron_to_spec/1) do
      [] -> resolve(%{step | "preferred_who" => nil})
      neurons -> neurons
    end
  end

  def resolve(%{"who" => who}), do: resolve_who(who)
  def resolve(step) when is_map(step), do: resolve_who(Map.get(step, "who", "all"))

  @doc """
  Resolve a full roster (list of roster entries) to a list of
  %{neurons: [...], when: ..., how: ...} maps.
  """
  def resolve_roster(roster) when is_list(roster) do
    Enum.map(roster, fn entry ->
      %{
        neurons: resolve(entry),
        when: Map.get(entry, "when", "sequential"),
        how: Map.get(entry, "how", "solo")
      }
    end)
  end

  def resolve_roster(_), do: []

  # --- Private ---

  defp resolve_who("all") do
    from(m in Neuron, where: m.type == "role" and m.status == "active")
    |> Repo.all()
    |> Enum.map(&neuron_to_spec/1)
  end

  defp resolve_who(rank) when rank in @rank_values, do: resolve_by_rank(rank)

  defp resolve_who("challenger") do
    case ExCortex.Neurons.Builtin.get("challenger") do
      nil -> []
      neuron ->
        rank_config = neuron.ranks[:journeyman]
        [%{provider: "ollama", model: rank_config.model, system_prompt: neuron.system_prompt, name: neuron.name, tools: []}]
    end
  end

  defp resolve_who("team:" <> team) do
    from(m in Neuron, where: m.type == "role" and m.status == "active" and m.team == ^team)
    |> Repo.all()
    |> Enum.map(&neuron_to_spec/1)
  end

  defp resolve_who(claude_tier) when claude_tier in ["claude_haiku", "claude_sonnet", "claude_opus"] do
    [%{provider: "claude", model: claude_tier, name: claude_tier, system_prompt: nil, tools: []}]
  end

  defp resolve_who(neuron_id) when is_binary(neuron_id) do
    case Repo.get(Neuron, neuron_id) do
      nil -> []
      m -> [neuron_to_spec(m)]
    end
  end

  defp resolve_who(_), do: []

  defp resolve_by_rank(rank) do
    from(m in Neuron,
      where: m.type == "role" and m.status == "active" and fragment("config->>'rank' = ?", ^rank)
    )
    |> Repo.all()
    |> Enum.map(&neuron_to_spec/1)
  end

  defp neuron_to_spec(db) do
    %{
      provider: db.config["provider"] || "ollama",
      model: db.config["model"] || "phi4-mini",
      system_prompt: db.config["system_prompt"] || "",
      name: db.name,
      tools: resolve_tools(db.config["tools"])
    }
  end

  defp resolve_tools(nil), do: []
  defp resolve_tools("all_safe"), do: ExCortex.Tools.Registry.resolve_tools(:all_safe)
  defp resolve_tools("write"), do: ExCortex.Tools.Registry.resolve_tools(:write)
  defp resolve_tools("dangerous"), do: ExCortex.Tools.Registry.resolve_tools(:dangerous)
  defp resolve_tools("yolo"), do: ExCortex.Tools.Registry.resolve_tools(:dangerous)
  defp resolve_tools(names) when is_list(names), do: ExCortex.Tools.Registry.resolve_tools(names)
  defp resolve_tools(_), do: []
end
```

**Step 4: Update ImpulseRunner to delegate to RosterResolver**

In `lib/ex_cortex/ruminations/impulse_runner.ex`, replace the private `resolve_neurons` functions (lines 223-333) with a delegation:

```elixir
  defp resolve_neurons(roster_entry) do
    ExCortex.Ruminations.RosterResolver.resolve(roster_entry)
  end
```

Keep the `@rank_values` module attribute if used elsewhere; remove if only used by the replaced functions.

**Step 5: Run all tests**

Run: `mix test test/ex_cortex/ruminations/roster_resolver_test.exs && mix test`
Expected: All pass

**Step 6: Commit**

```bash
git add lib/ex_cortex/ruminations/roster_resolver.ex test/ex_cortex/ruminations/roster_resolver_test.exs lib/ex_cortex/ruminations/impulse_runner.ex
git commit -m "refactor: extract RosterResolver from ImpulseRunner for UI reuse"
```

---

### Task 1: Add editing mode assigns and new rumination creation

Add the assigns and event handlers for toggling between view and edit mode, plus creating new ruminations.

**Files:**
- Modify: `lib/ex_cortex_web/live/ruminations_live.ex:8-28` (mount), add new event handlers

**Step 1: Write the test**

```elixir
# test/ex_cortex_web/live/ruminations_live_test.exs (add to existing or create)
defmodule ExCortexWeb.RuminationsLiveTest do
  use ExCortexWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "editing mode" do
    test "new_rumination enters edit mode with blank state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/ruminations")

      html = view |> element("[phx-click=new_rumination]") |> render_click()
      assert html =~ "new rumination"
    end

    test "edit_rumination enters edit mode with existing data", %{conn: conn} do
      rumination = insert_rumination("Test Pipeline")
      {:ok, view, _html} = live(conn, "/ruminations?id=#{rumination.id}")

      html = view |> element("[phx-click=edit_rumination]") |> render_click()
      assert html =~ "Test Pipeline"
      assert html =~ "save"
    end

    test "cancel_edit returns to view mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/ruminations")

      view |> element("[phx-click=new_rumination]") |> render_click()
      html = view |> element("[phx-click=cancel_edit]") |> render_click()
      refute html =~ "save"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: FAIL

**Step 3: Add assigns to mount**

In `mount/3`, add these assigns after existing ones:

```elixir
editing: false,
editing_rumination: nil,
pipeline_steps: [],
expanded_step: nil,
synapse_picker: nil,
synapse_search: "",
rumination_form: %{}
```

**Step 4: Add event handlers**

```elixir
def handle_event("new_rumination", _params, socket) do
  {:noreply,
   assign(socket,
     editing: true,
     editing_rumination: nil,
     pipeline_steps: [],
     expanded_step: nil,
     synapse_picker: nil,
     rumination_form: %{"name" => "", "description" => "", "trigger" => "manual", "schedule" => ""}
   )}
end

def handle_event("edit_rumination", _params, %{assigns: %{selected_rumination: rum}} = socket)
    when not is_nil(rum) do
  steps =
    rum.steps
    |> Enum.sort_by(&(&1["order"] || 0))
    |> Enum.with_index()
    |> Enum.map(fn {step, idx} ->
      synapse = Enum.find(socket.assigns.synapses, &(&1.id == step["step_id"]))
      %{
        "idx" => idx,
        "step_id" => step["step_id"],
        "synapse" => synapse,
        "gate" => Map.get(step, "gate", false),
        "type" => Map.get(step, "type", "linear"),
        "synthesizer" => Map.get(step, "synthesizer")
      }
    end)

  {:noreply,
   assign(socket,
     editing: true,
     editing_rumination: rum,
     pipeline_steps: steps,
     expanded_step: nil,
     synapse_picker: nil,
     rumination_form: %{
       "name" => rum.name,
       "description" => rum.description || "",
       "trigger" => rum.trigger,
       "schedule" => rum.schedule || ""
     }
   )}
end

def handle_event("cancel_edit", _params, socket) do
  {:noreply,
   assign(socket,
     editing: false,
     editing_rumination: nil,
     pipeline_steps: [],
     expanded_step: nil,
     synapse_picker: nil,
     rumination_form: %{}
   )}
end

def handle_event("update_rumination_form", %{"field" => field, "value" => value}, socket) do
  form = Map.put(socket.assigns.rumination_form, field, value)
  {:noreply, assign(socket, rumination_form: form)}
end
```

**Step 5: Run tests**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ex_cortex_web/live/ruminations_live.ex test/ex_cortex_web/live/ruminations_live_test.exs
git commit -m "feat: add editing mode assigns and event handlers for pipeline builder"
```

---

### Task 2: Render the pipeline builder panel (edit mode template)

Replace the right panel content when `@editing == true` with the builder layout: meta form + step chain + action bar.

**Files:**
- Modify: `lib/ex_cortex_web/live/ruminations_live.ex:258-381` (right panel render block)

**Step 1: Write the test**

```elixir
# Add to ruminations_live_test.exs
describe "builder panel" do
  test "shows meta form fields in edit mode", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/ruminations")
    html = view |> element("[phx-click=new_rumination]") |> render_click()

    assert html =~ "name"
    assert html =~ "trigger"
    assert html =~ ~s(phx-click="cancel_edit")
    assert html =~ ~s(phx-click="save_rumination")
  end

  test "shows empty step chain for new rumination", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/ruminations")
    html = view |> element("[phx-click=new_rumination]") |> render_click()

    assert html =~ "no steps"
    assert html =~ "+"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: FAIL

**Step 3: Add builder template**

In the render function, wrap the right panel in an editing check. When `@editing` is true, render the builder. This replaces the content inside `<div class="md:col-span-2 space-y-4">`:

```heex
<%= if @editing do %>
  <%!-- Pipeline Builder --%>
  <.panel title={if @editing_rumination, do: "edit: #{@rumination_form["name"]}", else: "new rumination"}>
    <div class="space-y-4">
      <%!-- Meta form --%>
      <div class="space-y-2">
        <div>
          <label class="text-xs t-dim uppercase tracking-wide">name</label>
          <input
            type="text"
            value={@rumination_form["name"]}
            phx-blur="update_rumination_form"
            phx-value-field="name"
            class="w-full h-8 text-sm border border-input rounded-md px-3 bg-background"
          />
        </div>
        <div>
          <label class="text-xs t-dim uppercase tracking-wide">description</label>
          <input
            type="text"
            value={@rumination_form["description"]}
            phx-blur="update_rumination_form"
            phx-value-field="description"
            class="w-full h-8 text-sm border border-input rounded-md px-3 bg-background"
          />
        </div>
        <div class="flex gap-4">
          <div class="flex-1">
            <label class="text-xs t-dim uppercase tracking-wide">trigger</label>
            <select
              phx-change="update_rumination_form"
              name="value"
              phx-value-field="trigger"
              class="w-full h-8 text-sm border border-input rounded-md px-2 bg-background"
            >
              <%= for t <- ~w(manual source scheduled once memory cortex) do %>
                <option value={t} selected={@rumination_form["trigger"] == t}>{t}</option>
              <% end %>
            </select>
          </div>
          <%= if @rumination_form["trigger"] in ~w(scheduled once) do %>
            <div class="flex-1">
              <label class="text-xs t-dim uppercase tracking-wide">schedule</label>
              <input
                type="text"
                value={@rumination_form["schedule"]}
                phx-blur="update_rumination_form"
                phx-value-field="schedule"
                placeholder="*/30 * * * *"
                class="w-full h-8 text-sm border border-input rounded-md px-3 bg-background"
              />
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Step chain --%>
      <div class="border-t pt-3">
        <p class="text-xs t-dim uppercase tracking-wide mb-2">synapse chain</p>
        <.step_chain steps={@pipeline_steps} expanded={@expanded_step} synapses={@synapses} picker={@synapse_picker} />
      </div>

      <%!-- Action bar --%>
      <div class="flex gap-2 border-t pt-3">
        <.button size="sm" phx-click="save_rumination">save</.button>
        <.button size="sm" variant="ghost" phx-click="cancel_edit">cancel</.button>
        <%= if @editing_rumination do %>
          <div class="flex-1" />
          <.button
            size="sm"
            variant="ghost"
            class="text-destructive"
            phx-click="delete_rumination"
            phx-value-id={@editing_rumination.id}
            data-confirm={"Delete \"#{@editing_rumination.name}\"?"}
          >
            delete
          </.button>
        <% end %>
      </div>
    </div>
  </.panel>
<% else %>
  <%!-- existing view mode template unchanged --%>
  ...
<% end %>
```

**Step 4: Add step_chain component stub**

```elixir
attr :steps, :list, required: true
attr :expanded, :any, default: nil
attr :synapses, :list, required: true
attr :picker, :any, default: nil

defp step_chain(assigns) do
  ~H"""
  <div class="font-mono text-sm" phx-window-keydown="step_chain_keydown">
    <%!-- Top inserter --%>
    <.step_inserter position={0} picker={@picker} />

    <%= if @steps == [] do %>
      <p class="text-xs t-dim italic py-2 pl-4">no steps — click [+] to add a synapse</p>
    <% end %>

    <%= for {step, idx} <- Enum.with_index(@steps) do %>
      <.step_card
        step={step}
        idx={idx}
        total={length(@steps)}
        expanded={@expanded == idx}
        synapses={@synapses}
      />
      <.step_inserter position={idx + 1} picker={@picker} />
    <% end %>
  </div>
  """
end
```

**Step 5: Run tests**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ex_cortex_web/live/ruminations_live.ex test/ex_cortex_web/live/ruminations_live_test.exs
git commit -m "feat: render pipeline builder panel in edit mode"
```

---

### Task 3: Step card component (compact + expanded views)

Build the step card with TUI box-drawing, compact summary, and expandable detail with roster editing.

**Files:**
- Modify: `lib/ex_cortex_web/live/ruminations_live.ex` — add `step_card`, `step_inserter` components

**Step 1: Write the test**

```elixir
# Add to ruminations_live_test.exs
describe "step card" do
  test "shows synapse name and neuron count in compact view", %{conn: conn} do
    synapse = insert_synapse("Code Review", [%{"who" => "master", "when" => "sequential", "how" => "solo"}])
    rumination = insert_rumination("Pipeline", [%{"step_id" => synapse.id, "order" => 1}])

    {:ok, view, _html} = live(conn, "/ruminations?id=#{rumination.id}")
    html = view |> element("[phx-click=edit_rumination]") |> render_click()

    assert html =~ "Code Review"
    assert html =~ "▲"
    assert html =~ "▼"
  end

  test "expand step shows roster editor", %{conn: conn} do
    synapse = insert_synapse("Code Review", [%{"who" => "master", "when" => "sequential", "how" => "solo"}])
    rumination = insert_rumination("Pipeline", [%{"step_id" => synapse.id, "order" => 1}])

    {:ok, view, _html} = live(conn, "/ruminations?id=#{rumination.id}")
    view |> element("[phx-click=edit_rumination]") |> render_click()
    html = view |> element("[phx-click=expand_step][phx-value-idx=0]") |> render_click()

    assert html =~ "who"
    assert html =~ "master"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: FAIL

**Step 3: Implement step_card component**

```elixir
attr :step, :map, required: true
attr :idx, :integer, required: true
attr :total, :integer, required: true
attr :expanded, :boolean, default: false
attr :synapses, :list, required: true

defp step_card(assigns) do
  synapse = assigns.step["synapse"]
  neuron_count = if synapse, do: length(synapse.roster || []), else: 0
  assigns = assign(assigns, synapse: synapse, neuron_count: neuron_count)

  ~H"""
  <div class={"border rounded px-3 py-2 " <> if(@expanded, do: "border-primary bg-muted/20", else: "border-input")}>
    <%!-- Compact header --%>
    <div class="flex items-center gap-2">
      <span class="t-dim font-mono text-xs w-4 shrink-0">{@idx + 1}.</span>
      <button class="flex-1 text-left truncate" phx-click="expand_step" phx-value-idx={@idx}>
        {if @synapse, do: @synapse.name, else: "unknown synapse"}
      </button>
      <span class="text-xs t-dim">◆ {@neuron_count}</span>
      <%= if @step["gate"] do %>
        <span class="text-xs t-red">▣ gate</span>
      <% end %>
      <%= if @step["type"] == "branch" do %>
        <span class="text-xs t-amber">⑂ branch</span>
      <% end %>
      <span class="flex gap-1">
        <button
          phx-click="move_step_up"
          phx-value-idx={@idx}
          disabled={@idx == 0}
          class={"text-xs px-1 " <> if(@idx == 0, do: "t-dim", else: "hover:bg-muted")}
          title="Move up (Alt+↑)"
        >▲</button>
        <button
          phx-click="move_step_down"
          phx-value-idx={@idx}
          disabled={@idx == @total - 1}
          class={"text-xs px-1 " <> if(@idx == @total - 1, do: "t-dim", else: "hover:bg-muted")}
          title="Move down (Alt+↓)"
        >▼</button>
        <button
          phx-click="remove_step"
          phx-value-idx={@idx}
          class="text-xs px-1 text-destructive hover:bg-muted"
          title="Remove (Alt+−)"
        >−</button>
      </span>
    </div>

    <%!-- Expanded detail --%>
    <%= if @expanded do %>
      <.step_detail step={@step} idx={@idx} synapse={@synapse} />
    <% end %>
  </div>
  """
end

defp step_detail(assigns) do
  ~H"""
  <div class="mt-3 pt-3 border-t border-dashed space-y-3">
    <%!-- Shared synapse warning --%>
    <.shared_synapse_warning synapse={@synapse} />

    <%!-- Roster editor --%>
    <div>
      <p class="text-xs t-dim uppercase tracking-wide mb-1">roster</p>
      <%= if @synapse && is_list(@synapse.roster) do %>
        <%= for {entry, ridx} <- Enum.with_index(@synapse.roster) do %>
          <div class="flex items-center gap-2 text-sm py-1">
            <span class="text-xs t-dim w-8">who:</span>
            <input
              type="text"
              value={Map.get(entry, "who", "")}
              phx-blur="update_roster_entry"
              phx-value-step-idx={@idx}
              phx-value-roster-idx={ridx}
              phx-value-field="who"
              class="flex-1 h-7 text-xs border border-input rounded px-2 bg-background"
              placeholder="all | master | team:Name | neuron_id"
            />
            <span class="text-xs t-dim w-10">when:</span>
            <select
              phx-change="update_roster_entry"
              name="value"
              phx-value-step-idx={@idx}
              phx-value-roster-idx={ridx}
              phx-value-field="when"
              class="h-7 text-xs border border-input rounded px-1 bg-background"
            >
              <option value="sequential" selected={Map.get(entry, "when") == "sequential"}>seq</option>
              <option value="parallel" selected={Map.get(entry, "when") == "parallel"}>par</option>
            </select>
            <span class="text-xs t-dim w-8">how:</span>
            <select
              phx-change="update_roster_entry"
              name="value"
              phx-value-step-idx={@idx}
              phx-value-roster-idx={ridx}
              phx-value-field="how"
              class="h-7 text-xs border border-input rounded px-1 bg-background"
            >
              <%= for h <- ~w(solo consensus majority) do %>
                <option value={h} selected={Map.get(entry, "how") == h}>{h}</option>
              <% end %>
            </select>
            <button
              phx-click="remove_roster_entry"
              phx-value-step-idx={@idx}
              phx-value-roster-idx={ridx}
              class="text-xs text-destructive px-1"
            >−</button>
          </div>
        <% end %>
      <% end %>
      <button
        phx-click="add_roster_entry"
        phx-value-step-idx={@idx}
        class="text-xs t-cyan hover:underline mt-1"
      >+ add roster entry</button>
    </div>

    <%!-- Resolved neuron preview --%>
    <.neuron_preview synapse={@synapse} />

    <%!-- Step options --%>
    <div class="flex gap-4 text-xs">
      <label class="flex items-center gap-1">
        <input
          type="checkbox"
          checked={@step["gate"]}
          phx-click="toggle_step_option"
          phx-value-idx={@idx}
          phx-value-option="gate"
        /> gate
      </label>
      <label class="flex items-center gap-1">
        <input
          type="checkbox"
          checked={@step["type"] == "branch"}
          phx-click="toggle_step_option"
          phx-value-idx={@idx}
          phx-value-option="branch"
        /> branch
      </label>
    </div>
  </div>
  """
end

defp shared_synapse_warning(assigns) do
  ~H"""
  <%!-- Populated in Task 5 when we add the usage count lookup --%>
  """
end

defp neuron_preview(assigns) do
  ~H"""
  <%!-- Populated in Task 4 when we wire up RosterResolver --%>
  """
end
```

**Step 4: Add expand/collapse, move, remove event handlers**

```elixir
def handle_event("expand_step", %{"idx" => idx_str}, socket) do
  idx = String.to_integer(idx_str)
  expanded = if socket.assigns.expanded_step == idx, do: nil, else: idx
  {:noreply, assign(socket, expanded_step: expanded)}
end

def handle_event("move_step_up", %{"idx" => idx_str}, socket) do
  idx = String.to_integer(idx_str)
  steps = socket.assigns.pipeline_steps

  if idx > 0 do
    steps = steps |> List.update_at(idx, &Map.put(&1, "idx", idx - 1))
                  |> List.update_at(idx - 1, &Map.put(&1, "idx", idx))
                  |> Enum.sort_by(& &1["idx"])
    {:noreply, assign(socket, pipeline_steps: steps, expanded_step: idx - 1)}
  else
    {:noreply, socket}
  end
end

def handle_event("move_step_down", %{"idx" => idx_str}, socket) do
  idx = String.to_integer(idx_str)
  steps = socket.assigns.pipeline_steps

  if idx < length(steps) - 1 do
    steps = steps |> List.update_at(idx, &Map.put(&1, "idx", idx + 1))
                  |> List.update_at(idx + 1, &Map.put(&1, "idx", idx))
                  |> Enum.sort_by(& &1["idx"])
    {:noreply, assign(socket, pipeline_steps: steps, expanded_step: idx + 1)}
  else
    {:noreply, socket}
  end
end

def handle_event("remove_step", %{"idx" => idx_str}, socket) do
  idx = String.to_integer(idx_str)
  steps = List.delete_at(socket.assigns.pipeline_steps, idx)
          |> Enum.with_index()
          |> Enum.map(fn {s, i} -> Map.put(s, "idx", i) end)
  expanded = if socket.assigns.expanded_step == idx, do: nil, else: socket.assigns.expanded_step
  {:noreply, assign(socket, pipeline_steps: steps, expanded_step: expanded)}
end
```

**Step 5: Run tests**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ex_cortex_web/live/ruminations_live.ex test/ex_cortex_web/live/ruminations_live_test.exs
git commit -m "feat: step card component with compact/expanded views and reordering"
```

---

### Task 4: Live neuron preview via RosterResolver

Wire up the resolved neuron preview in the expanded step card.

**Files:**
- Modify: `lib/ex_cortex_web/live/ruminations_live.ex` — fill in `neuron_preview` component, add resolver call

**Step 1: Write the test**

```elixir
# Add to ruminations_live_test.exs
describe "neuron preview" do
  test "shows resolved neuron names for roster", %{conn: conn} do
    insert_neuron("Code Bot", "role", "active", %{"rank" => "master"})
    synapse = insert_synapse("Review", [%{"who" => "master", "when" => "sequential", "how" => "solo"}])
    rumination = insert_rumination("Pipeline", [%{"step_id" => synapse.id, "order" => 1}])

    {:ok, view, _html} = live(conn, "/ruminations?id=#{rumination.id}")
    view |> element("[phx-click=edit_rumination]") |> render_click()
    html = view |> element("[phx-click=expand_step][phx-value-idx=0]") |> render_click()

    assert html =~ "Code Bot"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: FAIL

**Step 3: Implement neuron_preview component**

Replace the stub `neuron_preview` with:

```elixir
defp neuron_preview(assigns) do
  resolved =
    if assigns.synapse && is_list(assigns.synapse.roster) do
      ExCortex.Ruminations.RosterResolver.resolve_roster(assigns.synapse.roster)
    else
      []
    end

  all_neurons = resolved |> Enum.flat_map(& &1.neurons) |> Enum.uniq_by(& &1.name)
  assigns = assign(assigns, neurons: all_neurons)

  ~H"""
  <div>
    <p class="text-xs t-dim uppercase tracking-wide mb-1">resolved neurons</p>
    <%= if @neurons == [] do %>
      <p class="text-xs t-dim italic">no neurons match roster</p>
    <% else %>
      <div class="flex flex-wrap gap-2">
        <%= for n <- @neurons do %>
          <span class="text-xs px-2 py-0.5 rounded bg-muted t-bright">{n.name}</span>
        <% end %>
      </div>
    <% end %>
  </div>
  """
end
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/ruminations_live.ex test/ex_cortex_web/live/ruminations_live_test.exs
git commit -m "feat: live neuron preview in expanded step card via RosterResolver"
```

---

### Task 5: Roster editing event handlers

Add handlers for modifying roster entries (add, remove, update fields) and the shared synapse warning.

**Files:**
- Modify: `lib/ex_cortex_web/live/ruminations_live.ex` — add roster event handlers, fill in shared_synapse_warning

**Step 1: Write the test**

```elixir
describe "roster editing" do
  test "add_roster_entry adds a blank entry", %{conn: conn} do
    synapse = insert_synapse("Step1", [%{"who" => "all", "when" => "sequential", "how" => "solo"}])
    rumination = insert_rumination("P", [%{"step_id" => synapse.id, "order" => 1}])

    {:ok, view, _html} = live(conn, "/ruminations?id=#{rumination.id}")
    view |> element("[phx-click=edit_rumination]") |> render_click()
    view |> element("[phx-click=expand_step][phx-value-idx=0]") |> render_click()
    html = view |> element("[phx-click=add_roster_entry][phx-value-step-idx=0]") |> render_click()

    # Should now have 2 roster rows
    assert html |> Floki.find("[phx-value-roster-idx]") |> length() >= 2
  end

  test "remove_roster_entry removes the entry", %{conn: conn} do
    synapse = insert_synapse("Step1", [
      %{"who" => "all", "when" => "sequential", "how" => "solo"},
      %{"who" => "master", "when" => "parallel", "how" => "consensus"}
    ])
    rumination = insert_rumination("P", [%{"step_id" => synapse.id, "order" => 1}])

    {:ok, view, _html} = live(conn, "/ruminations?id=#{rumination.id}")
    view |> element("[phx-click=edit_rumination]") |> render_click()
    view |> element("[phx-click=expand_step][phx-value-idx=0]") |> render_click()
    html = view |> element("[phx-click=remove_roster_entry][phx-value-step-idx=0][phx-value-roster-idx=1]") |> render_click()

    refute html =~ "master"
  end
end
```

**Step 2: Run test to verify it fails**

**Step 3: Implement roster event handlers**

```elixir
def handle_event("add_roster_entry", %{"step-idx" => idx_str}, socket) do
  idx = String.to_integer(idx_str)
  steps = socket.assigns.pipeline_steps
  step = Enum.at(steps, idx)
  synapse = step["synapse"]

  if synapse do
    new_entry = %{"who" => "all", "when" => "sequential", "how" => "solo"}
    updated_roster = (synapse.roster || []) ++ [new_entry]
    updated_synapse = %{synapse | roster: updated_roster}
    updated_step = Map.put(step, "synapse", updated_synapse)
    steps = List.replace_at(steps, idx, updated_step)
    {:noreply, assign(socket, pipeline_steps: steps)}
  else
    {:noreply, socket}
  end
end

def handle_event("remove_roster_entry", %{"step-idx" => sidx, "roster-idx" => ridx}, socket) do
  sidx = String.to_integer(sidx)
  ridx = String.to_integer(ridx)
  steps = socket.assigns.pipeline_steps
  step = Enum.at(steps, sidx)
  synapse = step["synapse"]

  if synapse do
    updated_roster = List.delete_at(synapse.roster || [], ridx)
    updated_synapse = %{synapse | roster: updated_roster}
    updated_step = Map.put(step, "synapse", updated_synapse)
    steps = List.replace_at(steps, sidx, updated_step)
    {:noreply, assign(socket, pipeline_steps: steps)}
  else
    {:noreply, socket}
  end
end

def handle_event("update_roster_entry", %{"step-idx" => sidx, "roster-idx" => ridx, "field" => field, "value" => value}, socket) do
  sidx = String.to_integer(sidx)
  ridx = String.to_integer(ridx)
  steps = socket.assigns.pipeline_steps
  step = Enum.at(steps, sidx)
  synapse = step["synapse"]

  if synapse do
    roster = synapse.roster || []
    entry = Enum.at(roster, ridx) |> Map.put(field, value)
    updated_roster = List.replace_at(roster, ridx, entry)
    updated_synapse = %{synapse | roster: updated_roster}
    updated_step = Map.put(step, "synapse", updated_synapse)
    steps = List.replace_at(steps, sidx, updated_step)
    {:noreply, assign(socket, pipeline_steps: steps)}
  else
    {:noreply, socket}
  end
end

def handle_event("toggle_step_option", %{"idx" => idx_str, "option" => option}, socket) do
  idx = String.to_integer(idx_str)
  steps = socket.assigns.pipeline_steps
  step = Enum.at(steps, idx)

  updated_step = case option do
    "gate" -> Map.update(step, "gate", true, &(!&1))
    "branch" -> Map.update(step, "type", "branch", fn
      "branch" -> "linear"
      _ -> "branch"
    end)
    _ -> step
  end

  steps = List.replace_at(steps, idx, updated_step)
  {:noreply, assign(socket, pipeline_steps: steps)}
end
```

**Step 4: Fill in shared_synapse_warning**

```elixir
defp shared_synapse_warning(assigns) do
  usage_count =
    if assigns.synapse do
      assigns.synapse.id
      |> synapse_usage_count()
      |> Kernel.-(1)  # subtract current rumination
      |> max(0)
    else
      0
    end

  assigns = assign(assigns, usage_count: usage_count)

  ~H"""
  <%= if @usage_count > 0 do %>
    <div class="text-xs t-amber py-1">
      ⚠ shared — used in {@usage_count} other rumination{if @usage_count != 1, do: "s"}.
      Edits here affect all of them.
      <button phx-click="duplicate_synapse" phx-value-step-idx={@idx} class="t-cyan hover:underline ml-1">
        duplicate as new
      </button>
    </div>
  <% end %>
  """
end
```

Add helper:

```elixir
defp synapse_usage_count(synapse_id) do
  Ruminations.list_ruminations()
  |> Enum.count(fn r ->
    Enum.any?(r.steps || [], fn s -> s["step_id"] == synapse_id end)
  end)
end
```

**Step 5: Run tests**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ex_cortex_web/live/ruminations_live.ex test/ex_cortex_web/live/ruminations_live_test.exs
git commit -m "feat: roster editing handlers and shared synapse warning"
```

---

### Task 6: Synapse picker (insert existing or create new)

Build the inline synapse picker that appears at `[+]` insertion points.

**Files:**
- Modify: `lib/ex_cortex_web/live/ruminations_live.ex` — `step_inserter` component, picker event handlers

**Step 1: Write the test**

```elixir
describe "synapse picker" do
  test "clicking + opens picker at that position", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/ruminations")
    view |> element("[phx-click=new_rumination]") |> render_click()
    html = view |> element("[phx-click=open_picker][phx-value-position=0]") |> render_click()

    assert html =~ "existing"
    assert html =~ "new"
  end

  test "selecting existing synapse inserts step", %{conn: conn} do
    synapse = insert_synapse("MyStep", [])
    {:ok, view, _html} = live(conn, "/ruminations")
    view |> element("[phx-click=new_rumination]") |> render_click()
    view |> element("[phx-click=open_picker][phx-value-position=0]") |> render_click()
    html = view |> element("[phx-click=insert_synapse][phx-value-id=#{synapse.id}]") |> render_click()

    assert html =~ "MyStep"
  end

  test "creating new synapse inserts step", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/ruminations")
    view |> element("[phx-click=new_rumination]") |> render_click()
    view |> element("[phx-click=open_picker][phx-value-position=0]") |> render_click()
    html = view
           |> element("[phx-click=create_and_insert_synapse]")
           |> render_click(%{"name" => "Brand New Step"})

    assert html =~ "Brand New Step"
  end
end
```

**Step 2: Run test to verify it fails**

**Step 3: Implement step_inserter component**

```elixir
attr :position, :integer, required: true
attr :picker, :any, default: nil

defp step_inserter(assigns) do
  open = assigns.picker == assigns.position
  assigns = assign(assigns, open: open)

  ~H"""
  <div class="flex justify-center py-1">
    <%= if @open do %>
      <div class="border border-input rounded p-3 w-full space-y-2 bg-background">
        <div class="flex gap-2 text-xs">
          <button
            phx-click="picker_tab"
            phx-value-tab="existing"
            class="t-cyan hover:underline"
          >existing</button>
          <span class="t-dim">|</span>
          <button
            phx-click="picker_tab"
            phx-value-tab="new"
            class="t-cyan hover:underline"
          >new</button>
          <div class="flex-1" />
          <button phx-click="close_picker" class="t-dim hover:t-bright">✕</button>
        </div>
        <.picker_content position={@position} synapses={@synapses} search={@synapse_search} tab={@picker_tab} />
      </div>
    <% else %>
      <button
        phx-click="open_picker"
        phx-value-position={@position}
        class="text-xs t-dim hover:t-cyan px-2"
        title="Insert synapse (Enter)"
      >[+]</button>
    <% end %>
  </div>
  """
end
```

Note: This needs `@synapse_search`, `@picker_tab` assigns added to mount. Add `picker_tab: "existing"` to mount assigns.

**Step 4: Implement picker_content and event handlers**

```elixir
defp picker_content(assigns) do
  ~H"""
  <%= if @tab == "existing" do %>
    <div>
      <input
        type="text"
        value={@search}
        phx-keyup="picker_search"
        placeholder="search synapses…"
        class="w-full h-7 text-xs border border-input rounded px-2 bg-background mb-2"
        phx-debounce="200"
      />
      <div class="max-h-40 overflow-y-auto space-y-1">
        <%= for s <- filtered_synapses(@synapses, @search) do %>
          <button
            phx-click="insert_synapse"
            phx-value-id={s.id}
            phx-value-position={@position}
            class="w-full text-left text-xs px-2 py-1 rounded hover:bg-muted/40 flex items-center gap-2"
          >
            <span class="flex-1 truncate">{s.name}</span>
            <span class="t-dim">{s.cluster_name || "—"}</span>
            <span class="t-dim">◆ {length(s.roster || [])}</span>
          </button>
        <% end %>
      </div>
    </div>
  <% else %>
    <div class="space-y-2">
      <input
        type="text"
        id="new-synapse-name"
        placeholder="synapse name"
        phx-keyup="set_new_synapse_name"
        class="w-full h-7 text-xs border border-input rounded px-2 bg-background"
      />
      <.button size="sm" phx-click="create_and_insert_synapse" phx-value-position={@position}>
        create & insert
      </.button>
    </div>
  <% end %>
  """
end

defp filtered_synapses(synapses, ""), do: synapses
defp filtered_synapses(synapses, search) do
  term = String.downcase(search)
  Enum.filter(synapses, fn s -> String.contains?(String.downcase(s.name), term) end)
end
```

Event handlers:

```elixir
def handle_event("open_picker", %{"position" => pos_str}, socket) do
  pos = String.to_integer(pos_str)
  {:noreply, assign(socket, synapse_picker: pos, synapse_search: "", picker_tab: "existing")}
end

def handle_event("close_picker", _params, socket) do
  {:noreply, assign(socket, synapse_picker: nil)}
end

def handle_event("picker_tab", %{"tab" => tab}, socket) do
  {:noreply, assign(socket, picker_tab: tab)}
end

def handle_event("picker_search", %{"value" => val}, socket) do
  {:noreply, assign(socket, synapse_search: val)}
end

def handle_event("set_new_synapse_name", %{"value" => val}, socket) do
  {:noreply, assign(socket, new_synapse_name: val)}
end

def handle_event("insert_synapse", %{"id" => id_str, "position" => pos_str}, socket) do
  pos = String.to_integer(pos_str)
  synapse_id = String.to_integer(id_str)
  synapse = Enum.find(socket.assigns.synapses, &(&1.id == synapse_id))

  new_step = %{
    "idx" => pos,
    "step_id" => synapse_id,
    "synapse" => synapse,
    "gate" => false,
    "type" => "linear",
    "synthesizer" => nil
  }

  steps = List.insert_at(socket.assigns.pipeline_steps, pos, new_step)
          |> Enum.with_index()
          |> Enum.map(fn {s, i} -> Map.put(s, "idx", i) end)

  {:noreply, assign(socket, pipeline_steps: steps, synapse_picker: nil)}
end

def handle_event("create_and_insert_synapse", %{"position" => pos_str}, socket) do
  pos = String.to_integer(pos_str)
  name = socket.assigns[:new_synapse_name] || "New Synapse"

  case Ruminations.create_synapse(%{name: name, trigger: "manual", roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]}) do
    {:ok, synapse} ->
      new_step = %{
        "idx" => pos,
        "step_id" => synapse.id,
        "synapse" => synapse,
        "gate" => false,
        "type" => "linear",
        "synthesizer" => nil
      }

      steps = List.insert_at(socket.assigns.pipeline_steps, pos, new_step)
              |> Enum.with_index()
              |> Enum.map(fn {s, i} -> Map.put(s, "idx", i) end)

      synapses = Ruminations.list_synapses()

      {:noreply, assign(socket, pipeline_steps: steps, synapse_picker: nil, synapses: synapses)}

    {:error, _changeset} ->
      {:noreply, put_flash(socket, :error, "Failed to create synapse")}
  end
end
```

**Step 5: Run tests**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ex_cortex_web/live/ruminations_live.ex test/ex_cortex_web/live/ruminations_live_test.exs
git commit -m "feat: synapse picker — insert existing or create new synapse inline"
```

---

### Task 7: Save rumination (create and update)

Wire up the save button to persist the rumination with its step chain.

**Files:**
- Modify: `lib/ex_cortex_web/live/ruminations_live.ex` — add `save_rumination` handler
- Modify: `lib/ex_cortex/ruminations.ex` — ensure synapse updates work

**Step 1: Write the test**

```elixir
describe "save rumination" do
  test "creates new rumination with steps", %{conn: conn} do
    synapse = insert_synapse("Step1", [])
    {:ok, view, _html} = live(conn, "/ruminations")

    view |> element("[phx-click=new_rumination]") |> render_click()
    view |> render_blur("update_rumination_form", %{"field" => "name", "value" => "My Pipeline"})
    view |> element("[phx-click=open_picker][phx-value-position=0]") |> render_click()
    view |> element("[phx-click=insert_synapse][phx-value-id=#{synapse.id}]") |> render_click()
    html = view |> element("[phx-click=save_rumination]") |> render_click()

    assert html =~ "My Pipeline"
    refute html =~ "save"  # back in view mode
  end

  test "updates existing rumination", %{conn: conn} do
    synapse = insert_synapse("Step1", [])
    rumination = insert_rumination("Old Name", [%{"step_id" => synapse.id, "order" => 1}])

    {:ok, view, _html} = live(conn, "/ruminations?id=#{rumination.id}")
    view |> element("[phx-click=edit_rumination]") |> render_click()
    view |> render_blur("update_rumination_form", %{"field" => "name", "value" => "New Name"})
    html = view |> element("[phx-click=save_rumination]") |> render_click()

    assert html =~ "New Name"
  end
end
```

**Step 2: Run test to verify it fails**

**Step 3: Implement save_rumination handler**

```elixir
def handle_event("save_rumination", _params, socket) do
  form = socket.assigns.rumination_form
  steps = socket.assigns.pipeline_steps

  # Build steps array for storage
  step_data =
    steps
    |> Enum.with_index()
    |> Enum.map(fn {step, idx} ->
      base = %{"step_id" => step["step_id"], "order" => idx + 1}
      base = if step["gate"], do: Map.put(base, "gate", true), else: base
      base = if step["type"] == "branch", do: Map.put(base, "type", "branch"), else: base
      base = if step["synthesizer"], do: Map.put(base, "synthesizer", step["synthesizer"]), else: base
      base
    end)

  attrs = %{
    name: form["name"],
    description: form["description"],
    trigger: form["trigger"],
    schedule: form["schedule"],
    steps: step_data
  }

  # Save synapse roster changes
  Enum.each(steps, fn step ->
    if step["synapse"] do
      Ruminations.update_synapse(step["synapse"], %{roster: step["synapse"].roster})
    end
  end)

  result =
    if socket.assigns.editing_rumination do
      Ruminations.update_rumination(socket.assigns.editing_rumination, attrs)
    else
      Ruminations.create_rumination(attrs)
    end

  case result do
    {:ok, rumination} ->
      ruminations = Ruminations.list_ruminations()
      synapses = Ruminations.list_synapses()

      {:noreply,
       socket
       |> assign(
         editing: false,
         editing_rumination: nil,
         pipeline_steps: [],
         expanded_step: nil,
         ruminations: ruminations,
         synapses: synapses
       )
       |> load_rumination(rumination.id)
       |> put_flash(:info, "Rumination saved.")}

    {:error, changeset} ->
      {:noreply, put_flash(socket, :error, "Save failed: #{inspect(changeset.errors)}")}
  end
end
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/ruminations_live.ex test/ex_cortex_web/live/ruminations_live_test.exs
git commit -m "feat: save rumination — create/update with step chain and roster changes"
```

---

### Task 8: Keyboard navigation

Add keyboard bindings for navigating the step chain, expanding/collapsing, and operating the picker.

**Files:**
- Modify: `lib/ex_cortex_web/live/ruminations_live.ex` — add keydown handler, focus management

**Step 1: Write the test**

```elixir
describe "keyboard navigation" do
  test "arrow keys move focus between steps", %{conn: conn} do
    s1 = insert_synapse("Step1", [])
    s2 = insert_synapse("Step2", [])
    rumination = insert_rumination("P", [
      %{"step_id" => s1.id, "order" => 1},
      %{"step_id" => s2.id, "order" => 2}
    ])

    {:ok, view, _html} = live(conn, "/ruminations?id=#{rumination.id}")
    view |> element("[phx-click=edit_rumination]") |> render_click()

    # Focus first step, press down
    html = view |> render_keydown("step_chain_keydown", %{"key" => "ArrowDown"})
    # Should have focused_step = 0 or 1
    assert html =~ "Step1" or html =~ "Step2"
  end

  test "Enter expands focused step", %{conn: conn} do
    synapse = insert_synapse("Step1", [%{"who" => "all"}])
    rumination = insert_rumination("P", [%{"step_id" => synapse.id, "order" => 1}])

    {:ok, view, _html} = live(conn, "/ruminations?id=#{rumination.id}")
    view |> element("[phx-click=edit_rumination]") |> render_click()
    html = view |> render_keydown("step_chain_keydown", %{"key" => "Enter"})

    # Should expand step 0 (first focused step)
    assert html =~ "roster" or html =~ "who"
  end

  test "Escape closes expanded step or picker", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/ruminations")
    view |> element("[phx-click=new_rumination]") |> render_click()
    view |> element("[phx-click=open_picker][phx-value-position=0]") |> render_click()
    html = view |> render_keydown("step_chain_keydown", %{"key" => "Escape"})

    refute html =~ "existing"  # picker closed
  end
end
```

**Step 2: Run test to verify it fails**

**Step 3: Implement keyboard handler**

Add `focused_step: 0` to mount assigns. Then:

```elixir
def handle_event("step_chain_keydown", %{"key" => "ArrowDown"}, socket) do
  max = length(socket.assigns.pipeline_steps) - 1
  focused = min((socket.assigns[:focused_step] || 0) + 1, max)
  {:noreply, assign(socket, focused_step: focused)}
end

def handle_event("step_chain_keydown", %{"key" => "ArrowUp"}, socket) do
  focused = max((socket.assigns[:focused_step] || 0) - 1, 0)
  {:noreply, assign(socket, focused_step: focused)}
end

def handle_event("step_chain_keydown", %{"key" => "Enter"}, socket) do
  focused = socket.assigns[:focused_step] || 0
  expanded = if socket.assigns.expanded_step == focused, do: nil, else: focused
  {:noreply, assign(socket, expanded_step: expanded)}
end

def handle_event("step_chain_keydown", %{"key" => "Escape"}, socket) do
  cond do
    socket.assigns.synapse_picker != nil ->
      {:noreply, assign(socket, synapse_picker: nil)}
    socket.assigns.expanded_step != nil ->
      {:noreply, assign(socket, expanded_step: nil)}
    true ->
      {:noreply, socket}
  end
end

def handle_event("step_chain_keydown", %{"key" => "+"}, socket) when socket.assigns.editing do
  focused = socket.assigns[:focused_step] || 0
  {:noreply, assign(socket, synapse_picker: focused, synapse_search: "", picker_tab: "existing")}
end

def handle_event("step_chain_keydown", %{"key" => "-"}, socket) when socket.assigns.editing do
  focused = socket.assigns[:focused_step] || 0
  steps = socket.assigns.pipeline_steps

  if focused < length(steps) do
    steps = List.delete_at(steps, focused)
            |> Enum.with_index()
            |> Enum.map(fn {s, i} -> Map.put(s, "idx", i) end)
    {:noreply, assign(socket, pipeline_steps: steps, expanded_step: nil)}
  else
    {:noreply, socket}
  end
end

def handle_event("step_chain_keydown", _params, socket) do
  {:noreply, socket}
end
```

Add visual focus indicator to `step_card` — add a `focused` attr and highlight border:

```elixir
# In step_card, add attr:
attr :focused, :boolean, default: false

# Update border class:
class={"border rounded px-3 py-2 " <>
  cond do
    @expanded -> "border-primary bg-muted/20"
    @focused -> "border-cyan"
    true -> "border-input"
  end}
```

Pass `focused={@focused_step == idx}` from `step_chain` to `step_card`.

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/ruminations_live.ex test/ex_cortex_web/live/ruminations_live_test.exs
git commit -m "feat: keyboard navigation — arrows, enter, escape, +/- for step chain"
```

---

### Task 9: Branch visualization

Add visual fork/merge rendering for branch-type steps in the step chain.

**Files:**
- Modify: `lib/ex_cortex_web/live/ruminations_live.ex` — update `step_chain` to handle branch groups

**Step 1: Write the test**

```elixir
describe "branching" do
  test "toggling branch shows fork visualization", %{conn: conn} do
    s1 = insert_synapse("Analysis", [])
    s2 = insert_synapse("Synthesis", [])
    rumination = insert_rumination("P", [
      %{"step_id" => s1.id, "order" => 1},
      %{"step_id" => s2.id, "order" => 2}
    ])

    {:ok, view, _html} = live(conn, "/ruminations?id=#{rumination.id}")
    view |> element("[phx-click=edit_rumination]") |> render_click()
    view |> element("[phx-click=expand_step][phx-value-idx=0]") |> render_click()
    html = view |> element("input[phx-click=toggle_step_option][phx-value-option=branch]") |> render_click()

    assert html =~ "⑂" or html =~ "branch"
  end
end
```

**Step 2: Run test to verify it fails**

**Step 3: Update step_chain to group branches**

In the `step_chain` component, identify consecutive branch steps and render them in a fork layout:

```elixir
# In step_chain, replace the step iteration with branch-aware grouping:
<%= for group <- group_steps(@steps) do %>
  <%= case group do %>
    <% {:linear, step, idx} -> %>
      <.step_card step={step} idx={idx} total={length(@steps)} expanded={@expanded == idx} focused={@focused_step == idx} synapses={@synapses} />
      <.step_inserter position={idx + 1} picker={@picker} synapses={@synapses} search={@synapse_search} picker_tab={@picker_tab} />
    <% {:branch, branch_steps, synthesizer_idx} -> %>
      <div class="pl-4">
        <p class="text-xs t-dim font-mono">╱ ╲ branch</p>
        <div class="flex gap-2 pl-2 border-l border-dashed">
          <%= for {step, idx} <- branch_steps do %>
            <div class="flex-1">
              <.step_card step={step} idx={idx} total={length(@steps)} expanded={@expanded == idx} focused={@focused_step == idx} synapses={@synapses} />
            </div>
          <% end %>
        </div>
        <p class="text-xs t-dim font-mono">╲ ╱ merge</p>
      </div>
      <%= if synthesizer_idx do %>
        <.step_card step={Enum.at(@steps, synthesizer_idx)} idx={synthesizer_idx} total={length(@steps)} expanded={@expanded == synthesizer_idx} focused={@focused_step == synthesizer_idx} synapses={@synapses} />
      <% end %>
      <.step_inserter position={(synthesizer_idx || List.last(branch_steps) |> elem(1)) + 1} picker={@picker} synapses={@synapses} search={@synapse_search} picker_tab={@picker_tab} />
  <% end %>
<% end %>
```

Add helper:

```elixir
defp group_steps(steps) do
  steps
  |> Enum.with_index()
  |> Enum.chunk_by(fn {step, _idx} -> step["type"] == "branch" end)
  |> Enum.flat_map(fn chunk ->
    case chunk do
      [{%{"type" => "branch"}, _} | _] = branches ->
        [{:branch, branches, nil}]
      linear_steps ->
        Enum.map(linear_steps, fn {step, idx} -> {:linear, step, idx} end)
    end
  end)
end
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/ruminations_live.ex test/ex_cortex_web/live/ruminations_live_test.exs
git commit -m "feat: branch fork/merge visualization with ASCII art"
```

---

### Task 10: Duplicate synapse and left panel "new" button

Add the "duplicate as new synapse" action and the "New Rumination" button in the left panel.

**Files:**
- Modify: `lib/ex_cortex_web/live/ruminations_live.ex`

**Step 1: Write the test**

```elixir
describe "duplicate synapse" do
  test "creates a copy with new name", %{conn: conn} do
    synapse = insert_synapse("Shared Step", [%{"who" => "master"}])
    rumination = insert_rumination("P", [%{"step_id" => synapse.id, "order" => 1}])

    {:ok, view, _html} = live(conn, "/ruminations?id=#{rumination.id}")
    view |> element("[phx-click=edit_rumination]") |> render_click()
    view |> element("[phx-click=expand_step][phx-value-idx=0]") |> render_click()
    html = view |> element("[phx-click=duplicate_synapse][phx-value-step-idx=0]") |> render_click()

    assert html =~ "Shared Step (copy)"
  end
end
```

**Step 2: Run test to verify it fails**

**Step 3: Implement duplicate_synapse handler**

```elixir
def handle_event("duplicate_synapse", %{"step-idx" => idx_str}, socket) do
  idx = String.to_integer(idx_str)
  step = Enum.at(socket.assigns.pipeline_steps, idx)
  synapse = step["synapse"]

  if synapse do
    attrs = %{
      name: synapse.name <> " (copy)",
      trigger: synapse.trigger,
      roster: synapse.roster,
      description: synapse.description,
      output_type: synapse.output_type,
      context_providers: synapse.context_providers,
      cluster_name: synapse.cluster_name,
      min_rank: synapse.min_rank
    }

    case Ruminations.create_synapse(attrs) do
      {:ok, new_synapse} ->
        updated_step = step
                       |> Map.put("synapse", new_synapse)
                       |> Map.put("step_id", new_synapse.id)
        steps = List.replace_at(socket.assigns.pipeline_steps, idx, updated_step)
        synapses = Ruminations.list_synapses()

        {:noreply, assign(socket, pipeline_steps: steps, synapses: synapses)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to duplicate synapse")}
    end
  else
    {:noreply, socket}
  end
end
```

**Step 4: Add "new" button to left panel**

In the render function, add a button above or below the rumination list in the left panel:

```heex
<%!-- Add at top of left panel, inside .panel --%>
<button
  phx-click="new_rumination"
  class="w-full text-left px-2 py-1.5 rounded text-sm t-cyan hover:bg-muted/40 transition-colors mb-2"
>
  [+] new rumination
</button>
```

**Step 5: Run tests**

Run: `mix test test/ex_cortex_web/live/ruminations_live_test.exs`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ex_cortex_web/live/ruminations_live.ex test/ex_cortex_web/live/ruminations_live_test.exs
git commit -m "feat: duplicate synapse action and new rumination button"
```

---

### Task 11: Update key_hints and final polish

Update the key hints bar, wire up the "Edit" button (currently a no-op navigation), and do a formatting pass.

**Files:**
- Modify: `lib/ex_cortex_web/live/ruminations_live.ex`

**Step 1: Update key_hints**

Change line 222 from:
```elixir
<.key_hints hints={[{"n", "new"}, {"r", "run"}, {"d", "delete"}, {"esc", "back"}]} />
```

To dynamically switch based on mode:

```elixir
<.key_hints hints={
  if @editing do
    [{"↑↓", "navigate"}, {"enter", "expand"}, {"+", "insert"}, {"−", "remove"}, {"esc", "close"}]
  else
    [{"n", "new"}, {"e", "edit"}, {"r", "run"}, {"d", "delete"}, {"esc", "back"}]
  end
} />
```

**Step 2: Wire up the Edit button**

Replace the current Edit button (line 337-343) which navigates to `/ruminations` (no-op) with:

```heex
<.button
  size="sm"
  variant="ghost"
  phx-click="edit_rumination"
>
  Edit
</.button>
```

**Step 3: Add global keyboard shortcuts for view mode**

```elixir
def handle_event("keydown", %{"key" => "n"}, %{assigns: %{editing: false}} = socket) do
  {:noreply, socket |> handle_event_result("new_rumination", %{})}
end

def handle_event("keydown", %{"key" => "e"}, %{assigns: %{editing: false, selected_rumination: rum}} = socket)
    when not is_nil(rum) do
  {:noreply, socket |> handle_event_result("edit_rumination", %{})}
end
```

Actually, simpler: add `phx-window-keydown="global_keydown"` to the top-level div and handle there.

**Step 4: Format**

Run: `mix format`

**Step 5: Run full test suite**

Run: `mix test`
Expected: All pass

**Step 6: Commit**

```bash
git add lib/ex_cortex_web/live/ruminations_live.ex
git commit -m "feat: key hints, edit button wiring, and keyboard shortcuts for pipeline builder"
```
