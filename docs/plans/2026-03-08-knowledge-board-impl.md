# Lore Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a persistent lore where artifact quests write synthesized entries, humans can CRUD them manually, and verdict quests can read them back as context.

**Architecture:** New `lore_entries` table + `ExCalibur.Lore` context module. Quests gain `output_type` ("verdict"|"artifact"), `write_mode` ("append"|"replace"), `entry_title_template`. `QuestRunner` detects artifact quests and writes entries instead of verdicts. New `/grimoire` LiveView. New `lore` context provider.

**Tech Stack:** Phoenix LiveView, Ecto, SaladUI.Badge, existing `ContextProviders` behaviour pattern, existing `QuestRunner` pattern.

---

## Task 1: Migrations

**Files:**
- Create: `priv/repo/migrations/20260308280000_add_artifact_fields_to_quests.exs`
- Create: `priv/repo/migrations/20260308290000_create_lore_entries.exs`

**Step 1: Write the quests migration**

```elixir
# priv/repo/migrations/20260308280000_add_artifact_fields_to_quests.exs
defmodule ExCalibur.Repo.Migrations.AddArtifactFieldsToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :output_type, :string, default: "verdict"
      add :write_mode, :string, default: "append"
      add :entry_title_template, :string
    end
  end
end
```

**Step 2: Write the lore_entries migration**

```elixir
# priv/repo/migrations/20260308290000_create_lore_entries.exs
defmodule ExCalibur.Repo.Migrations.CreateKnowledgeEntries do
  use Ecto.Migration

  def change do
    create table(:lore_entries) do
      add :quest_id, :integer
      add :title, :string, null: false
      add :body, :text, default: ""
      add :tags, {:array, :string}, default: []
      add :importance, :integer
      add :source, :string, default: "quest"
      timestamps()
    end

    create index(:lore_entries, [:quest_id])
    create index(:lore_entries, [:source])
  end
end
```

**Step 3: Run migrations**

```bash
cd /home/andrew/projects/ex_calibur && mix ecto.migrate
```

Expected: both migrations run successfully.

**Step 4: Commit**

```bash
git add priv/repo/migrations/
git commit -m "feat: migrations for artifact quests and lore_entries"
```

---

## Task 2: LoreEntry Schema + Knowledge Context Module

**Files:**
- Create: `lib/ex_calibur/lore/lore_entry.ex`
- Create: `lib/ex_calibur/lore.ex`

**Step 1: Write the schema**

```elixir
# lib/ex_calibur/lore/lore_entry.ex
defmodule ExCalibur.Lore.LoreEntry do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "lore_entries" do
    field :quest_id, :integer
    field :title, :string
    field :body, :string, default: ""
    field :tags, {:array, :string}, default: []
    field :importance, :integer
    field :source, :string, default: "quest"
    timestamps()
  end

  @required [:title]
  @optional [:quest_id, :body, :tags, :importance, :source]

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:source, ["quest", "manual"])
    |> validate_number(:importance, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
  end
end
```

**Step 2: Write the context module**

```elixir
# lib/ex_calibur/lore.ex
defmodule ExCalibur.Lore do
  @moduledoc false
  import Ecto.Query

  alias ExCalibur.Lore.LoreEntry
  alias ExCalibur.Repo

  def list_entries(opts \\ []) do
    tags = Keyword.get(opts, :tags, [])
    quest_id = Keyword.get(opts, :quest_id)
    sort = Keyword.get(opts, :sort, "newest")

    query =
      from(e in LoreEntry)
      |> filter_tags(tags)
      |> filter_quest(quest_id)
      |> apply_sort(sort)

    Repo.all(query)
  end

  def get_entry!(id), do: Repo.get!(LoreEntry, id)

  def create_entry(attrs) do
    %LoreEntry{} |> LoreEntry.changeset(attrs) |> Repo.insert()
  end

  def update_entry(%LoreEntry{} = entry, attrs) do
    entry |> LoreEntry.changeset(attrs) |> Repo.update()
  end

  def delete_entry(%LoreEntry{} = entry), do: Repo.delete(entry)

  @doc """
  Used by artifact quest runs. Appends or replaces based on quest write_mode.
  Only replaces entries with source: "quest" (never overwrites manually edited).
  """
  def write_artifact(quest, attrs) do
    if quest.write_mode == "replace" do
      case Repo.one(from e in LoreEntry,
             where: e.quest_id == ^quest.id and e.source == "quest",
             limit: 1) do
        nil -> create_entry(Map.put(attrs, :quest_id, quest.id))
        existing -> update_entry(existing, attrs)
      end
    else
      create_entry(Map.put(attrs, :quest_id, quest.id))
    end
  end

  defp filter_tags(query, []), do: query
  defp filter_tags(query, tags) do
    from e in query, where: fragment("? && ?", e.tags, ^tags)
  end

  defp filter_quest(query, nil), do: query
  defp filter_quest(query, quest_id) do
    from e in query, where: e.quest_id == ^quest_id
  end

  defp apply_sort(query, "importance") do
    from e in query, order_by: [desc_nulls_last: e.importance, desc: e.inserted_at]
  end
  defp apply_sort(query, _newest) do
    from e in query, order_by: [desc: e.inserted_at]
  end
end
```

**Step 3: Write a test**

```elixir
# test/ex_calibur/lore_test.exs
defmodule ExCalibur.LoreTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Lore
  alias ExCalibur.Lore.LoreEntry

  test "create and list entries" do
    {:ok, _} = Lore.create_entry(%{title: "Test Entry", body: "hello", tags: ["a11y"]})
    entries = Lore.list_entries()
    assert length(entries) == 1
    assert hd(entries).title == "Test Entry"
  end

  test "list_entries filters by tags" do
    {:ok, _} = Lore.create_entry(%{title: "A11y", tags: ["a11y"]})
    {:ok, _} = Lore.create_entry(%{title: "Security", tags: ["security"]})
    entries = Lore.list_entries(tags: ["a11y"])
    assert length(entries) == 1
    assert hd(entries).title == "A11y"
  end

  test "write_artifact append mode creates new entries each time" do
    quest = %{id: 1, write_mode: "append"}
    {:ok, _} = Knowledge.write_artifact(quest, %{title: "Entry 1"})
    {:ok, _} = Knowledge.write_artifact(quest, %{title: "Entry 2"})
    entries = Lore.list_entries(quest_id: 1)
    assert length(entries) == 2
  end

  test "write_artifact replace mode overwrites quest-owned entry" do
    quest = %{id: 2, write_mode: "replace"}
    {:ok, _} = Knowledge.write_artifact(quest, %{title: "First"})
    {:ok, _} = Knowledge.write_artifact(quest, %{title: "Updated"})
    entries = Lore.list_entries(quest_id: 2)
    assert length(entries) == 1
    assert hd(entries).title == "Updated"
  end

  test "write_artifact replace mode does not overwrite manually edited entry" do
    quest = %{id: 3, write_mode: "replace"}
    {:ok, entry} = Knowledge.write_artifact(quest, %{title: "Original"})
    # Simulate human edit
    {:ok, _} = Knowledge.update_entry(entry, %{title: "Human Edited", source: "manual"})
    # Quest tries to replace
    {:ok, _} = Knowledge.write_artifact(quest, %{title: "Quest Override"})
    entries = Lore.list_entries(quest_id: 3)
    # Human edit preserved, new entry appended
    assert length(entries) == 2
    titles = Enum.map(entries, & &1.title)
    assert "Human Edited" in titles
    assert "Quest Override" in titles
  end
end
```

**Step 4: Run tests**

```bash
cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur/lore_test.exs 2>&1
```

Expected: 4 tests, 0 failures.

**Step 5: Commit**

```bash
git add lib/ex_calibur/lore.ex lib/ex_calibur/lore/ test/ex_calibur/lore_test.exs
git commit -m "feat: LoreEntry schema and Knowledge context module"
```

---

## Task 3: Update Quest Schema

**Files:**
- Modify: `lib/ex_calibur/quests/quest.ex`

**Step 1: Add fields**

```elixir
# lib/ex_calibur/quests/quest.ex
defmodule ExCalibur.Quests.Quest do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "excellence_quests" do
    field :name, :string
    field :description, :string
    field :status, :string
    field :trigger, :string
    field :schedule, :string
    field :roster, {:array, :map}, default: []
    field :context_providers, {:array, :map}, default: []
    field :source_ids, {:array, :string}, default: []
    field :output_type, :string, default: "verdict"
    field :write_mode, :string, default: "append"
    field :entry_title_template, :string
    timestamps()
  end

  @required [:name, :trigger]
  @optional [:description, :status, :schedule, :roster, :context_providers, :source_ids,
             :output_type, :write_mode, :entry_title_template]

  def changeset(quest, attrs) do
    quest
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["active", "paused"])
    |> validate_inclusion(:trigger, ["manual", "source", "scheduled"])
    |> validate_inclusion(:output_type, ["verdict", "artifact"])
    |> validate_inclusion(:write_mode, ["append", "replace"])
    |> unique_constraint(:name)
  end
end
```

**Step 2: Run existing tests to make sure nothing broke**

```bash
cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur_web/live/quests_live_test.exs 2>&1
```

Expected: 7 tests, 0 failures.

**Step 3: Commit**

```bash
git add lib/ex_calibur/quests/quest.ex
git commit -m "feat: add output_type, write_mode, entry_title_template to Quest"
```

---

## Task 4: QuestRunner Artifact Support

**Files:**
- Modify: `lib/ex_calibur/quest_runner.ex`

**Step 1: Update `run/2` to branch on output_type**

Replace the existing `run(quest, input_text) when is_struct(quest)` clause with:

```elixir
def run(%{output_type: "artifact"} = quest, input_text) do
  context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
  augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"
  result = run_artifact(quest, augmented)

  case result do
    {:ok, attrs} ->
      ExCalibur.Lore.write_artifact(quest, attrs)
      {:ok, %{artifact: attrs}}

    error ->
      error
  end
end

def run(quest, input_text) when is_struct(quest) do
  context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
  augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"
  run(quest.roster, augmented)
end
```

**Step 2: Add `run_artifact/2` and `parse_artifact/1`**

Add these private functions to `quest_runner.ex`:

```elixir
defp run_artifact(quest, input_text) do
  ollama_url = Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434")
  ollama = Ollama.new(base_url: ollama_url)

  # Use the first roster step's member config, or default to all active members
  members =
    case quest.roster do
      [first | _] -> resolve_members(first["who"])
      _ -> resolve_members("all")
    end

  member = List.first(members)

  if is_nil(member) do
    {:error, :no_members}
  else
    system_prompt = artifact_system_prompt(quest)
    messages = [
      %{role: :system, content: system_prompt},
      %{role: :user, content: input_text}
    ]

    raw =
      case member do
        %{type: :claude, tier: tier} ->
          case ClaudeClient.complete(tier, system_prompt, input_text) do
            {:ok, text} -> text
            _ -> nil
          end

        %{type: :ollama, model: model} ->
          case Ollama.chat(ollama, model, messages) do
            {:ok, %{content: text}} -> text
            {:ok, text} when is_binary(text) -> text
            _ -> nil
          end
      end

    if raw do
      date = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")
      title_template = quest.entry_title_template || quest.name || "Entry — {date}"
      title = String.replace(title_template, "{date}", date)

      {:ok, parse_artifact(raw, title)}
    else
      {:error, :llm_failed}
    end
  end
end

defp artifact_system_prompt(quest) do
  instruction = quest.description || "Synthesize the provided content."

  """
  #{instruction}

  Respond in this exact format:
  TITLE: <a concise title for this entry>
  IMPORTANCE: <integer 1-5, where 5 is most important, or omit if not applicable>
  TAGS: <comma-separated tags, lowercase, e.g. a11y,security,deps>
  BODY:
  <your synthesized content here, markdown is fine>
  """
end

defp parse_artifact(text, fallback_title) do
  title =
    case Regex.run(~r/^TITLE:\s*(.+)$/m, text) do
      [_, t] -> String.trim(t)
      _ -> fallback_title
    end

  importance =
    case Regex.run(~r/^IMPORTANCE:\s*(\d)$/m, text) do
      [_, n] ->
        val = String.to_integer(n)
        if val in 1..5, do: val, else: nil
      _ -> nil
    end

  tags =
    case Regex.run(~r/^TAGS:\s*(.+)$/m, text) do
      [_, t] ->
        t |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
      _ -> []
    end

  body =
    case Regex.run(~r/^BODY:\s*\n(.*)/ms, text) do
      [_, b] -> String.trim(b)
      _ -> text
    end

  %{title: title, body: body, tags: tags, importance: importance, source: "quest"}
end
```

**Step 3: Run the existing quest tests**

```bash
cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur_web/live/quests_live_test.exs 2>&1
```

Expected: 7 tests, 0 failures.

**Step 4: Commit**

```bash
git add lib/ex_calibur/quest_runner.ex
git commit -m "feat: QuestRunner artifact output type — writes to lore"
```

---

## Task 5: Lore Context Provider

**Files:**
- Create: `lib/ex_calibur/context_providers/lore.ex`
- Modify: `lib/ex_calibur/context_providers/context_provider.ex`

**Step 1: Write the provider**

```elixir
# lib/ex_calibur/context_providers/lore.ex
defmodule ExCalibur.ContextProviders.Lore do
  @moduledoc """
  Injects lore entries as prompt context.
  Config: %{"type" => "lore", "tags" => ["a11y"], "limit" => 10, "sort" => "importance"}
  """

  @behaviour ExCalibur.ContextProviders.ContextProvider

  alias ExCalibur.Lore

  @impl true
  def build(config, _quest, _input) do
    tags = Map.get(config, "tags", [])
    limit = Map.get(config, "limit", 10)
    sort = Map.get(config, "sort", "newest")

    entries = Lore.list_entries(tags: tags, sort: sort) |> Enum.take(limit)

    if entries == [] do
      ""
    else
      lines =
        Enum.map(entries, fn entry ->
          importance = if entry.importance, do: " [importance: #{entry.importance}]", else: ""
          tags_str = if entry.tags != [], do: "\nTags: #{Enum.join(entry.tags, ", ")}", else: ""
          "### #{entry.title}#{importance}#{tags_str}\n#{entry.body}"
        end)

      String.trim("""
      ## Lore Context
      #{Enum.join(lines, "\n\n")}
      """)
    end
  end
end
```

**Step 2: Register it in context_provider.ex**

In `lib/ex_calibur/context_providers/context_provider.ex`, add one line in `module_for/1`:

```elixir
defp module_for("lore"), do: Module.concat([ExCalibur, ContextProviders, Lore])
```

(After the existing `module_for("member_stats")` clause.)

**Step 3: Write a test**

```elixir
# test/ex_calibur/context_providers/lore_test.exs
defmodule ExCalibur.ContextProviders.LoreTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.ContextProviders.Lore
  alias ExCalibur.Lore

  test "returns empty string when no entries" do
    result = Lore.build(%{"type" => "lore"}, %{}, "input")
    assert result == ""
  end

  test "injects entries as markdown context" do
    {:ok, _} = Lore.create_entry(%{title: "A11y news", body: "Some content", tags: ["a11y"], importance: 4})
    result = Lore.build(%{"type" => "lore", "tags" => ["a11y"]}, %{}, "")
    assert result =~ "Lore Context"
    assert result =~ "A11y news"
    assert result =~ "importance: 4"
    assert result =~ "Some content"
  end

  test "respects limit" do
    for i <- 1..5 do
      Lore.create_entry(%{title: "Entry #{i}"})
    end
    result = Lore.build(%{"type" => "lore", "limit" => 2}, %{}, "")
    # Should only include 2 entries
    assert length(Regex.scan(~r/### Entry/, result)) == 2
  end
end
```

**Step 4: Run tests**

```bash
cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur/context_providers/lore_test.exs 2>&1
```

Expected: 3 tests, 0 failures.

**Step 5: Commit**

```bash
git add lib/ex_calibur/context_providers/lore.ex lib/ex_calibur/context_providers/context_provider.ex test/ex_calibur/context_providers/
git commit -m "feat: lore context provider"
```

---

## Task 6: Lore LiveView

**Files:**
- Create: `lib/ex_calibur_web/live/grimoire_live.ex`
- Modify: `lib/ex_calibur_web/router.ex`
- Modify: `lib/ex_calibur_web/components/layouts/root.html.heex`

**Step 1: Write the LiveView**

```elixir
# lib/ex_calibur_web/live/grimoire_live.ex
defmodule ExCaliburWeb.GrimoireLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge

  alias ExCalibur.Lore
  alias ExCalibur.Lore.LoreEntry
  alias ExCalibur.Quests

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Grimoire",
       entries: Lore.list_entries(),
       quests: Quests.list_quests(),
       filter_tags: [],
       filter_quest_id: nil,
       sort: "newest",
       adding: false,
       editing_id: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_tag_filter", %{"tag" => tag}, socket) do
    tags =
      if tag in socket.assigns.filter_tags,
        do: List.delete(socket.assigns.filter_tags, tag),
        else: [tag | socket.assigns.filter_tags]

    {:noreply, reload(assign(socket, filter_tags: tags))}
  end

  def handle_event("filter_quest", %{"quest_id" => ""}, socket) do
    {:noreply, reload(assign(socket, filter_quest_id: nil))}
  end

  def handle_event("filter_quest", %{"quest_id" => id}, socket) do
    {:noreply, reload(assign(socket, filter_quest_id: String.to_integer(id)))}
  end

  def handle_event("set_sort", %{"sort" => sort}, socket) do
    {:noreply, reload(assign(socket, sort: sort))}
  end

  def handle_event("add_entry", _, socket) do
    {:noreply, assign(socket, adding: true, editing_id: nil)}
  end

  def handle_event("cancel", _, socket) do
    {:noreply, assign(socket, adding: false, editing_id: nil)}
  end

  def handle_event("create_entry", %{"entry" => params}, socket) do
    attrs = parse_entry_params(params) |> Map.put(:source, "manual")
    case Lore.create_entry(attrs) do
      {:ok, _} -> {:noreply, reload(assign(socket, adding: false))}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create entry")}
    end
  end

  def handle_event("edit_entry", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_id: String.to_integer(id), adding: false)}
  end

  def handle_event("update_entry", %{"id" => id, "entry" => params}, socket) do
    entry = Knowledge.get_entry!(String.to_integer(id))
    attrs = parse_entry_params(params) |> Map.put(:source, "manual")
    case Knowledge.update_entry(entry, attrs) do
      {:ok, _} -> {:noreply, reload(assign(socket, editing_id: nil))}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to update entry")}
    end
  end

  def handle_event("delete_entry", %{"id" => id}, socket) do
    entry = Knowledge.get_entry!(String.to_integer(id))
    Knowledge.delete_entry(entry)
    {:noreply, reload(socket)}
  end

  defp reload(socket) do
    entries = Lore.list_entries(
      tags: socket.assigns.filter_tags,
      quest_id: socket.assigns.filter_quest_id,
      sort: socket.assigns.sort
    )
    assign(socket, entries: entries)
  end

  defp parse_entry_params(params) do
    tags =
      (params["tags"] || "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    importance =
      case Integer.parse(params["importance"] || "") do
        {n, ""} when n in 1..5 -> n
        _ -> nil
      end

    %{
      title: params["title"] || "",
      body: params["body"] || "",
      tags: tags,
      importance: importance
    }
  end

  defp quest_name(quests, quest_id) when is_integer(quest_id) do
    case Enum.find(quests, &(&1.id == quest_id)) do
      nil -> "Quest ##{quest_id}"
      quest -> quest.name
    end
  end

  defp importance_dots(nil), do: "○○○○○"
  defp importance_dots(n) do
    filled = String.duplicate("●", n)
    empty = String.duplicate("○", 5 - n)
    filled <> empty
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 class="text-3xl font-bold tracking-tight">Knowledge</h1>
          <p class="text-muted-foreground mt-1.5">
            Synthesized artifacts and curated entries from your guild's quests.
          </p>
        </div>
        <.button variant="outline" phx-click="add_entry" class="self-start sm:mt-1">
          + New Entry
        </.button>
      </div>

      <%# Filter bar %>
      <div class="flex flex-wrap items-center gap-3">
        <select
          phx-change="filter_quest"
          name="quest_id"
          class="h-8 text-sm border border-input rounded-md px-2 bg-background focus:outline-none"
        >
          <option value="">All quests</option>
          <%= for quest <- @quests do %>
            <option value={quest.id} selected={@filter_quest_id == quest.id}>{quest.name}</option>
          <% end %>
        </select>
        <div class="flex gap-1">
          <button
            phx-click="set_sort"
            phx-value-sort="newest"
            class={["px-3 py-1 text-xs rounded-md border transition-colors",
              if(@sort == "newest", do: "bg-accent text-foreground border-accent", else: "border-border text-muted-foreground hover:bg-muted")
            ]}
          >Newest</button>
          <button
            phx-click="set_sort"
            phx-value-sort="importance"
            class={["px-3 py-1 text-xs rounded-md border transition-colors",
              if(@sort == "importance", do: "bg-accent text-foreground border-accent", else: "border-border text-muted-foreground hover:bg-muted")
            ]}
          >Importance</button>
        </div>
        <%= if @filter_tags != [] do %>
          <div class="flex flex-wrap gap-1 items-center">
            <span class="text-xs text-muted-foreground">Filtered:</span>
            <%= for tag <- @filter_tags do %>
              <button phx-click="toggle_tag_filter" phx-value-tag={tag}>
                <.badge variant="default" class="text-xs cursor-pointer">{tag} ✕</.badge>
              </button>
            <% end %>
          </div>
        <% end %>
      </div>

      <%# New entry form %>
      <%= if @adding do %>
        <.entry_form id="new-entry" submit_event="create_entry" entry={nil} />
      <% end %>

      <%# Entry feed %>
      <%= if @entries == [] do %>
        <div class="rounded-lg border p-8 text-center">
          <p class="text-muted-foreground text-sm">
            No entries yet. Create one manually or run an artifact quest.
          </p>
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for entry <- @entries do %>
            <%= if @editing_id == entry.id do %>
              <.entry_form id={"edit-#{entry.id}"} submit_event="update_entry" entry={entry} />
            <% else %>
              <.entry_card
                entry={entry}
                quest_name={if entry.quest_id, do: quest_name(@quests, entry.quest_id), else: nil}
                active_tags={@filter_tags}
              />
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :quest_name, :string, default: nil
  attr :active_tags, :list, default: []

  defp entry_card(assigns) do
    ~H"""
    <div class="rounded-lg border bg-card p-5 space-y-3">
      <div class="flex items-start justify-between gap-3">
        <div class="space-y-1 flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="font-medium truncate">{@entry.title}</span>
            <%= if @entry.importance do %>
              <span class="text-xs text-muted-foreground font-mono shrink-0">
                {importance_dots(@entry.importance)}
              </span>
            <% end %>
            <%= if @entry.source == "manual" do %>
              <span class="text-xs text-muted-foreground shrink-0" title="Manually curated">✎</span>
            <% end %>
          </div>
          <%= if @entry.tags != [] do %>
            <div class="flex flex-wrap gap-1">
              <%= for tag <- @entry.tags do %>
                <button phx-click="toggle_tag_filter" phx-value-tag={tag}>
                  <.badge
                    variant={if tag in @active_tags, do: "default", else: "outline"}
                    class="text-xs cursor-pointer"
                  >{tag}</.badge>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
        <div class="flex gap-2 shrink-0">
          <.button
            variant="outline"
            size="sm"
            phx-click="edit_entry"
            phx-value-id={@entry.id}
          >Edit</.button>
          <.button
            variant="destructive"
            size="sm"
            phx-click="delete_entry"
            phx-value-id={@entry.id}
            data-confirm={if @entry.source == "quest", do: "This entry will be re-generated on the next quest run unless you change the quest's write mode.", else: "Delete this entry?"}
          >✕</.button>
        </div>
      </div>
      <%= if @entry.body && @entry.body != "" do %>
        <div class="text-sm text-foreground/80 whitespace-pre-wrap border-t pt-3">
          {@entry.body}
        </div>
      <% end %>
      <div class="text-xs text-muted-foreground border-t pt-2 flex items-center gap-2">
        <%= if @quest_name do %>
          <span>From: {@quest_name}</span>
          <span>·</span>
        <% else %>
          <span>Manual</span>
          <span>·</span>
        <% end %>
        <span>
          <%= if @entry.source == "quest" and @entry.inserted_at != @entry.updated_at do %>
            Last updated {Calendar.strftime(@entry.updated_at, "%b %d %H:%M")}
          <% else %>
            {Calendar.strftime(@entry.inserted_at, "%b %d %H:%M")}
          <% end %>
        </span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :submit_event, :string, required: true
  attr :entry, :map, required: true

  defp entry_form(assigns) do
    ~H"""
    <div class="rounded-lg border border-dashed p-5">
      <form phx-submit={@submit_event} class="space-y-3">
        <%= if @entry do %>
          <input type="hidden" name="id" value={@entry.id} />
        <% end %>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <label class="text-sm font-medium">Title</label>
            <.input type="text" name="entry[title]" value={if @entry, do: @entry.title, else: ""} placeholder="Entry title" />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-sm font-medium">Importance</label>
              <select name="entry[importance]" class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring">
                <option value="">None</option>
                <%= for n <- 1..5 do %>
                  <option value={n} selected={@entry && @entry.importance == n}>{n}</option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="text-sm font-medium">Tags</label>
              <.input type="text" name="entry[tags]" value={if @entry, do: Enum.join(@entry.tags, ", "), else: ""} placeholder="a11y, security" />
            </div>
          </div>
        </div>
        <div>
          <label class="text-sm font-medium">Body (markdown)</label>
          <.input type="textarea" name="entry[body]" value={if @entry, do: @entry.body, else: ""} rows={4} placeholder="Content…" />
        </div>
        <div class="flex justify-end gap-2">
          <.button type="button" variant="outline" size="sm" phx-click="cancel">Cancel</.button>
          <.button type="submit" size="sm">
            {if @entry, do: "Save changes", else: "Create Entry"}
          </.button>
        </div>
      </form>
    </div>
    """
  end
end
```

**Step 2: Add route to router.ex**

In `lib/ex_calibur_web/router.ex`, inside the `scope "/", ExCaliburWeb` block, add:

```elixir
live "/grimoire", GrimoireLive, :index
```

**Step 3: Add Knowledge to nav in root.html.heex**

Replace the nav list:

```heex
{"Lodge", "/lodge"},
{"Members", "/members"},
{"Quests", "/quests"},
{"Grimoire", "/grimoire"},
{"Library", "/library"},
{"Town Square", "/town-square"},
{"Guild Hall", "/guild-hall"}
```

**Step 4: Run compile check**

```bash
cd /home/andrew/projects/ex_calibur && mix compile 2>&1
```

Expected: no warnings, no errors.

**Step 5: Write a basic test**

```elixir
# test/ex_calibur_web/live/grimoire_live_test.exs
defmodule ExCaliburWeb.GrimoireLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCalibur.Lore

  test "renders empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "Grimoire"
    assert html =~ "No entries yet"
  end

  test "renders existing entries", %{conn: conn} do
    {:ok, _} = Lore.create_entry(%{title: "My entry", body: "hello", tags: ["test"]})
    {:ok, view, html} = live(conn, "/grimoire")
    html_snapshot(view)
    assert html =~ "My entry"
    assert html =~ "test"
  end

  test "create entry manually", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/grimoire")
    render_click(view, "add_entry", %{})

    view
    |> form("form[phx-submit=\"create_entry\"]", %{
      "entry" => %{"title" => "Manual Entry", "body" => "Some content", "tags" => "a11y", "importance" => "3"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Manual Entry"
  end

  test "delete entry", %{conn: conn} do
    {:ok, entry} = Lore.create_entry(%{title: "To Delete"})
    {:ok, view, _html} = live(conn, "/grimoire")
    assert render(view) =~ "To Delete"
    render_click(view, "delete_entry", %{"id" => to_string(entry.id)})
    refute render(view) =~ "To Delete"
  end
end
```

**Step 6: Run tests**

```bash
cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur_web/live/grimoire_live_test.exs 2>&1
```

Expected: 4 tests, 0 failures.

**Step 7: Commit**

```bash
git add lib/ex_calibur_web/live/grimoire_live.ex lib/ex_calibur_web/router.ex lib/ex_calibur_web/components/layouts/root.html.heex test/ex_calibur_web/live/grimoire_live_test.exs
git commit -m "feat: Grimoire LiveView at /grimoire"
```

---

## Task 7: Quest Form — Artifact Output Fields

**Files:**
- Modify: `lib/ex_calibur_web/live/quests_live.ex`

**Step 1: Add output_type preview tracking to mount**

In `mount/3`, add to `trigger_previews` equivalent for output type. Add `output_previews` to assigns:

```elixir
output_previews =
  Map.new(quests, fn q -> {"quest-#{q.id}", q.output_type || "verdict"} end)
  |> Map.put("new-quest", "verdict")
```

Add `output_previews: output_previews` to the `assign` call.

**Step 2: Add `preview_quest_output` event handlers**

```elixir
@impl true
def handle_event("preview_new_quest_output", %{"quest" => %{"output_type" => t}}, socket) do
  {:noreply, assign(socket, output_previews: Map.put(socket.assigns.output_previews, "new-quest", t))}
end
def handle_event("preview_new_quest_output", _params, socket), do: {:noreply, socket}

@impl true
def handle_event("preview_quest_output", %{"quest_id" => id, "quest" => %{"output_type" => t}}, socket) do
  {:noreply, assign(socket, output_previews: Map.put(socket.assigns.output_previews, "quest-#{id}", t))}
end
def handle_event("preview_quest_output", _params, socket), do: {:noreply, socket}
```

**Step 3: Add `output_type`, `write_mode`, `entry_title_template` to create/update quest handlers**

In `handle_event("create_quest", ...)`:

```elixir
output_type = params["output_type"] || "verdict"
write_mode = if output_type == "artifact", do: params["write_mode"] || "append", else: "append"
entry_title_template = if output_type == "artifact", do: params["entry_title_template"], else: nil
```

Add to `attrs`:

```elixir
output_type: output_type,
write_mode: write_mode,
entry_title_template: entry_title_template,
```

Do the same in `handle_event("update_quest", ...)`.

**Step 4: Add `output_type` preview rebuild in `rebuild_trigger_previews`**

Rename to also handle output previews, or add a separate `rebuild_output_previews/3` helper:

```elixir
defp rebuild_output_previews(quests, existing) do
  existing
  |> Map.merge(Map.new(quests, fn q -> {"quest-#{q.id}", q.output_type || "verdict"} end))
end
```

Call it in `create_quest`, `update_quest` handlers alongside `rebuild_trigger_previews`.

**Step 5: Update `new_quest_form` component**

Add `attr :output_preview, :string, default: "verdict"` and `attr :sources, :list` already exists.

Add the output type selector after the trigger fields, and conditional artifact fields:

```heex
<div>
  <label for="quest-output-type" class="text-sm font-medium">Output</label>
  <select
    id="quest-output-type"
    name="quest[output_type]"
    class="w-full text-sm border rounded px-2 py-1 bg-background"
  >
    <option value="verdict" selected={@output_preview == "verdict"}>Verdict (pass/warn/fail)</option>
    <option value="artifact" selected={@output_preview == "artifact"}>Artifact (write to Knowledge)</option>
  </select>
</div>
<%= if @output_preview == "artifact" do %>
  <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
    <div>
      <label class="text-sm font-medium">Write mode</label>
      <select name="quest[write_mode]" class="w-full text-sm border rounded px-2 py-1 bg-background">
        <option value="append">Append (each run adds an entry)</option>
        <option value="replace">Replace (overwrite previous entry)</option>
      </select>
    </div>
    <div>
      <label class="text-sm font-medium">Title template</label>
      <.input type="text" name="quest[entry_title_template]" value="" placeholder="Summary — {date}" />
    </div>
  </div>
<% end %>
```

Add `phx-change="preview_new_quest_output"` to the form tag (alongside existing `preview_new_quest_trigger`). Since a form can only have one `phx-change`, merge into the existing handler or use a combined event. The cleanest solution: add output_type handling to the existing `preview_new_quest_trigger` handler by also reading `output_type` from params.

Update `preview_new_quest_trigger` to also update output_previews:

```elixir
def handle_event("preview_new_quest_trigger", params, socket) do
  t = get_in(params, ["quest", "trigger"])
  o = get_in(params, ["quest", "output_type"])

  socket =
    if t, do: assign(socket, trigger_previews: Map.put(socket.assigns.trigger_previews, "new-quest", t)), else: socket
  socket =
    if o, do: assign(socket, output_previews: Map.put(socket.assigns.output_previews, "new-quest", o)), else: socket

  {:noreply, socket}
end
```

Do the same for the existing `preview_quest_trigger`, `preview_campaign_trigger` handlers (output_type won't be on campaigns).

**Step 6: Do the same for `quest_card` edit form**

Pass `output_preview={@output_previews["quest-#{quest.id}"] || quest.output_type || "verdict"}` to `quest_card`. Add attr, show the output type selector and artifact fields.

Also hide "Escalate on" when `output_preview == "artifact"` in the quest_card form.

**Step 7: Pass `output_previews` everywhere**

Pass `output_previews` to render calls: `new_quest_form` and `quest_card`.

**Step 8: Run tests**

```bash
cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur_web/live/quests_live_test.exs 2>&1
```

Expected: 7 tests, 0 failures.

**Step 9: Commit**

```bash
git add lib/ex_calibur_web/live/quests_live.ex
git commit -m "feat: artifact output type fields in quest create/edit forms"
```

---

## Task 8: Quest Form — Lore Context Provider Option

**Files:**
- Modify: `lib/ex_calibur_web/live/quests_live.ex`

**Step 1: Add "Knowledge board" to context type dropdown**

In both `new_quest_form` and `quest_card`, find the context type select and add:

```heex
<option value="lore">Knowledge board</option>
```

**Step 2: Add conditional lore config fields**

After the context select in both forms, add:

```heex
<%= if context_type shows "lore" do %>
  <%# Need to track context_type in assigns similar to trigger_preview %>
  <div class="grid grid-cols-3 gap-2 mt-1">
    <div>
      <label class="text-xs text-muted-foreground">Tags (comma-sep)</label>
      <.input type="text" name="quest[kb_tags]" value="" placeholder="a11y, security" />
    </div>
    <div>
      <label class="text-xs text-muted-foreground">Limit</label>
      <.input type="number" name="quest[kb_limit]" value="10" min="1" />
    </div>
    <div>
      <label class="text-xs text-muted-foreground">Sort</label>
      <select name="quest[kb_sort]" class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background">
        <option value="newest">Newest</option>
        <option value="importance">Importance</option>
      </select>
    </div>
  </div>
<% end %>
```

To show/hide this, add `context_previews` tracking to assigns (similar to `trigger_previews`/`output_previews`). Track `"new-quest"` and `"quest-#{id}"` keys. Update existing `preview_new_quest_trigger` handler to also read `context_type` from params and update `context_previews`.

**Step 3: Update create/update handlers to build lore context provider**

In `handle_event("create_quest", ...)` and `handle_event("update_quest", ...)`, update `context_providers` assembly:

```elixir
context_providers =
  case params["context_type"] do
    "static" -> ...  # existing
    "quest_history" -> ...  # existing
    "member_stats" -> ...  # existing
    "lore" ->
      tags =
        (params["kb_tags"] || "")
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      limit = String.to_integer(params["kb_limit"] || "10")
      sort = params["kb_sort"] || "newest"
      [%{"type" => "lore", "tags" => tags, "limit" => limit, "sort" => sort}]
    _ -> []
  end
```

**Step 4: Run all tests**

```bash
cd /home/andrew/projects/ex_calibur && mix test 2>&1
```

Expected: all tests pass, 0 failures.

**Step 5: Commit**

```bash
git add lib/ex_calibur_web/live/quests_live.ex
git commit -m "feat: lore context provider option in quest form"
```

---

## Task 9: Final — Run Full Test Suite

```bash
cd /home/andrew/projects/ex_calibur && mix test 2>&1
```

Expected: all tests pass, 0 failures, 0 warnings.

If accessibility snapshot tests fail (html_snapshots need updating), run:

```bash
cd /home/andrew/projects/ex_calibur && mix test --update-snapshots 2>&1
```

Then commit updated snapshots:

```bash
git add test/excessibility/html_snapshots/
git commit -m "chore: update accessibility snapshots for lore"
```

---

## Implementation Order Summary

1. Migrations → Quest schema → Knowledge schema+context
2. QuestRunner artifact branch → Lore context provider
3. `/grimoire` LiveView + route + nav
4. Quest form: output type + artifact fields
5. Quest form: lore context option
6. Full test suite pass
