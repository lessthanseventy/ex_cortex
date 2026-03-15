# Jarvis Life Dashboard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add Lodge as a first-class quest trigger and rebuild Everyday Council as a one-click full life OS with 11 feeds, 8 steps, auto-recruited members, and daily/weekly/monthly briefings.

**Architecture:** New `LodgeTriggerRunner` GenServer mirrors `LoreTriggerRunner` — subscribes to `"lodge"` PubSub, fires matching quests on card create. Quest schema gets two new array fields for lodge trigger filtering. Everyday Council template expanded with all lifestyle feeds and briefing steps. Individual lifestyle templates gated with `{:not_installed, "everyday_council"}`.

**Tech Stack:** Elixir, Ecto, Phoenix PubSub, Phoenix LiveView

---

### Task 1: Migration — Add Lodge Trigger Fields to Quests

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_lodge_trigger_fields_to_quests.exs`
- Modify: `lib/ex_cortex/quests/quest.ex`

**Step 1: Create the migration**

```elixir
defmodule ExCortex.Repo.Migrations.AddLodgeTriggerFieldsToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :lodge_trigger_types, {:array, :string}, default: []
      add :lodge_trigger_tags, {:array, :string}, default: []
    end
  end
end
```

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix ecto.migrate' --pane=main:1.3`

**Step 2: Update Quest schema**

In `lib/ex_cortex/quests/quest.ex`:

Add fields after `lore_trigger_tags`:
```elixir
field :lodge_trigger_types, {:array, :string}, default: []
field :lodge_trigger_tags, {:array, :string}, default: []
```

Add `"lodge"` to trigger validation:
```elixir
|> validate_inclusion(:trigger, ["manual", "source", "scheduled", "once", "lore", "lodge"])
```

Add both fields to `@optional`:
```elixir
@optional [:description, :status, :schedule, :run_at, :steps, :source_ids, :lore_trigger_tags, :lodge_trigger_types, :lodge_trigger_tags]
```

**Step 3: Run tests**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/quests 2>&1 | tail -10' --pane=main:1.3`

**Step 4: Commit**

```bash
git add priv/repo/migrations/*lodge_trigger* lib/ex_cortex/quests/quest.ex
git commit -m "feat: add lodge_trigger_types and lodge_trigger_tags fields to quests"
```

---

### Task 2: LodgeTriggerRunner GenServer

**Files:**
- Create: `lib/ex_cortex/lodge_trigger_runner.ex`
- Modify: `lib/ex_cortex/application.ex` (add to supervision tree)

**Step 1: Create LodgeTriggerRunner**

Create `lib/ex_cortex/lodge_trigger_runner.ex`:

```elixir
defmodule ExCortex.LodgeTriggerRunner do
  @moduledoc """
  Listens for new lodge cards and fires any quests with trigger: "lodge"
  whose lodge_trigger_types/lodge_trigger_tags overlap the card's type/tags.
  """
  use GenServer

  alias ExCortex.QuestRunner
  alias ExCortex.Quests

  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "lodge")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:lodge_card_posted, card}, state) do
    try do
      Quests.list_quests()
      |> Enum.filter(fn q ->
        q.trigger == "lodge" && q.status == "active" &&
          types_match?(q.lodge_trigger_types, card.type) &&
          tags_match?(q.lodge_trigger_tags, card.tags || [])
      end)
      |> Enum.each(fn quest ->
        Logger.info("[LodgeTriggerRunner] Firing quest #{quest.id} (#{quest.name}) on lodge card #{card.id}")
        input = build_input(card)
        Task.start(fn -> QuestRunner.run(quest, input) end)
      end)
    rescue
      e in DBConnection.OwnershipError ->
        _ = e
        :ok

      e ->
        Logger.warning("[LodgeTriggerRunner] Error processing lodge card #{card.id}: #{inspect(e)}")
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # empty types = match all cards
  defp types_match?([], _card_type), do: true
  defp types_match?(types, card_type), do: card_type in types

  # empty tags = match all cards
  defp tags_match?([], _card_tags), do: true
  defp tags_match?(trigger_tags, card_tags), do: Enum.any?(trigger_tags, &(&1 in card_tags))

  defp build_input(card) do
    tags_str = if card.tags != [], do: "\nTags: #{Enum.join(card.tags, ", ")}", else: ""
    "## #{card.title}\nType: #{card.type}#{tags_str}\n\n#{card.body || ""}"
  end
end
```

**Step 2: Add to supervision tree**

In `lib/ex_cortex/application.ex`, add after `ExCortex.LoreTriggerRunner`:

```elixir
ExCortex.LodgeTriggerRunner,
```

**Step 3: Compile and verify**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors 2>&1 | tail -5' --pane=main:1.3`

**Step 4: Commit**

```bash
git add lib/ex_cortex/lodge_trigger_runner.ex lib/ex_cortex/application.ex
git commit -m "feat: add LodgeTriggerRunner GenServer for lodge-triggered quests"
```

---

### Task 3: Lodge Trigger UI in Quests LiveView

**Files:**
- Modify: `lib/ex_cortex_web/live/quests_live.ex`

**Step 1: Add "Lodge" option to BOTH trigger dropdowns**

In the **new quest form** (around line 904), add after the lore option:
```elixir
<option value="lodge">Lodge</option>
```

In the **edit quest form** (around line 1089), add after the lore option:
```elixir
<option value="lodge" selected={@quest.trigger == "lodge"}>
  Lodge
</option>
```

**Step 2: Add lodge trigger config UI to BOTH forms**

After the `<%= if @trigger_preview == "lore" do %>` block in the **new quest form** (after line 946), add:

```elixir
<%= if @trigger_preview == "lodge" do %>
  <div class="space-y-2">
    <div>
      <label class="text-sm font-medium">Card types (optional)</label>
      <input
        type="text"
        name="quest[lodge_trigger_types]"
        value=""
        placeholder="todo, checklist, note… (empty = all)"
        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
      />
      <p class="text-xs text-muted-foreground mt-1">
        Fires when a lodge card of these types is created.
      </p>
    </div>
    <div>
      <label class="text-sm font-medium">Card tags (optional)</label>
      <input
        type="text"
        name="quest[lodge_trigger_tags]"
        value=""
        placeholder="urgent, todo… (empty = all)"
        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
      />
    </div>
  </div>
<% end %>
```

Add the same block after the lore block in the **edit quest form** (after line 1139), with values pre-filled:

```elixir
<%= if @trigger_preview == "lodge" do %>
  <div class="space-y-2">
    <div>
      <label class="text-sm font-medium">Card types (optional)</label>
      <input
        type="text"
        name="quest[lodge_trigger_types]"
        value={Enum.join(@quest.lodge_trigger_types || [], ", ")}
        placeholder="todo, checklist, note… (empty = all)"
        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
      />
      <p class="text-xs text-muted-foreground mt-1">
        Fires when a lodge card of these types is created.
      </p>
    </div>
    <div>
      <label class="text-sm font-medium">Card tags (optional)</label>
      <input
        type="text"
        name="quest[lodge_trigger_tags]"
        value={Enum.join(@quest.lodge_trigger_tags || [], ", ")}
        placeholder="urgent, todo… (empty = all)"
        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
      />
    </div>
  </div>
<% end %>
```

**Step 3: Wire lodge trigger fields in create/update handlers**

In `handle_event("create_quest", ...)` (around line 280), add parsing after `lore_trigger_tags`:

```elixir
lodge_trigger_types =
  (params["lodge_trigger_types"] || "")
  |> String.split(",")
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))

lodge_trigger_tags =
  (params["lodge_trigger_tags"] || "")
  |> String.split(",")
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))
```

Add both to the `attrs` map:
```elixir
lodge_trigger_types: lodge_trigger_types,
lodge_trigger_tags: lodge_trigger_tags,
```

Do the same in `handle_event("update_quest", ...)` (around line 352).

**Step 4: Compile and run tests**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors && mix test test/ex_cortex_web/live/quests_live_test.exs 2>&1 | tail -10' --pane=main:1.3`

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/quests_live.ex
git commit -m "feat: add Lodge trigger option to quest UI with type/tag filters"
```

---

### Task 4: Board Requirement — {:not_installed, id}

**Files:**
- Modify: `lib/ex_cortex/board.ex`

**Step 1: Add `:not_installed` requirement handler**

In `check_requirements/1` (around line 51), add a new clause to the `Enum.map` function:

```elixir
{:not_installed, template_id} ->
  installed =
    Repo.exists?(
      from(q in ExCortex.Quests.Quest,
        where: q.status in ["active", "paused"],
        where: like(q.name, ^"%#{template_id_to_quest_prefix(template_id)}%")
      )
    )

  # Requirement is met when the conflicting template is NOT installed
  {!installed, "Not included in #{humanize(template_id)}"}
```

Add the helper function:

```elixir
defp template_id_to_quest_prefix("everyday_council"), do: "Everyday Council"
defp template_id_to_quest_prefix(id), do: humanize(id)
```

**Step 2: Compile and verify**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors 2>&1 | tail -5' --pane=main:1.3`

**Step 3: Commit**

```bash
git add lib/ex_cortex/board.ex
git commit -m "feat: add {:not_installed, id} requirement type for board templates"
```

---

### Task 5: Gate Individual Lifestyle Templates

**Files:**
- Modify: `lib/ex_cortex/board/lifestyle.ex`

**Step 1: Add requirement to each individual template**

Add `{:not_installed, "everyday_council"}` to the `requires` list of each individual template:

- `tech_dispatch`: `requires: [:any_members, {:not_installed, "everyday_council"}]`
- `sports_corner`: `requires: [:any_members, {:not_installed, "everyday_council"}]`
- `market_signals`: `requires: [:any_members, {:not_installed, "everyday_council"}]`
- `culture_desk`: `requires: [:any_members, {:not_installed, "everyday_council"}]`
- `science_watch`: `requires: [:any_members, {:not_installed, "everyday_council"}]`

**Step 2: Compile**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors 2>&1 | tail -5' --pane=main:1.3`

**Step 3: Commit**

```bash
git add lib/ex_cortex/board/lifestyle.ex
git commit -m "feat: gate individual lifestyle templates when Everyday Council is installed"
```

---

### Task 6: Rebuild Everyday Council — Sources

**Files:**
- Modify: `lib/ex_cortex/board/lifestyle.ex`

**Step 1: Expand source_definitions in everyday_council**

Replace the current `source_definitions` (just the webhook) with the full set:

```elixir
source_definitions: [
  # Personal intake
  %{
    name: "Personal Inbox Webhook",
    source_type: "webhook",
    config: %{"secret" => ""}
  },
  # Tech
  %{
    name: "Hacker News",
    source_type: "feed",
    config: %{"url" => "https://news.ycombinator.com/rss", "interval" => 1_800_000},
    book_id: "hacker_news_rss"
  },
  %{
    name: "The Verge",
    source_type: "feed",
    config: %{"url" => "https://www.theverge.com/rss/index.xml", "interval" => 1_800_000},
    book_id: "the_verge_rss"
  },
  %{
    name: "Ars Technica",
    source_type: "feed",
    config: %{"url" => "https://feeds.arstechnica.com/arstechnica/index", "interval" => 1_800_000},
    book_id: "ars_technica_rss"
  },
  # Business
  %{
    name: "Reuters Business",
    source_type: "feed",
    config: %{"url" => "https://feeds.reuters.com/reuters/businessNews", "interval" => 1_800_000},
    book_id: "reuters_business_rss"
  },
  %{
    name: "Financial Times",
    source_type: "feed",
    config: %{"url" => "https://www.ft.com/rss/home", "interval" => 1_800_000},
    book_id: "ft_rss"
  },
  # Sports
  %{
    name: "ESPN",
    source_type: "feed",
    config: %{"url" => "https://www.espn.com/espn/rss/news", "interval" => 1_800_000},
    book_id: "espn_rss"
  },
  %{
    name: "BBC Sport",
    source_type: "feed",
    config: %{"url" => "http://feeds.bbci.co.uk/sport/rss.xml", "interval" => 1_800_000},
    book_id: "bbc_sport_rss"
  },
  # Culture
  %{
    name: "Pitchfork",
    source_type: "feed",
    config: %{"url" => "https://pitchfork.com/rss/news/", "interval" => 3_600_000},
    book_id: "pitchfork_rss"
  },
  %{
    name: "AV Club",
    source_type: "feed",
    config: %{"url" => "https://www.avclub.com/rss", "interval" => 3_600_000},
    book_id: "av_club_rss"
  },
  # Science
  %{
    name: "Science Daily",
    source_type: "feed",
    config: %{"url" => "https://www.sciencedaily.com/rss/all.xml", "interval" => 3_600_000},
    book_id: "science_daily_rss"
  },
  %{
    name: "Nature News",
    source_type: "feed",
    config: %{"url" => "https://www.nature.com/nature.rss", "interval" => 3_600_000},
    book_id: "nature_news_rss"
  }
],
```

**Step 2: Compile**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors 2>&1 | tail -5' --pane=main:1.3`

**Step 3: Commit**

```bash
git add lib/ex_cortex/board/lifestyle.ex
git commit -m "feat: wire 12 sources into Everyday Council (webhook + 11 feeds)"
```

---

### Task 7: Rebuild Everyday Council — Steps

**Files:**
- Modify: `lib/ex_cortex/board/lifestyle.ex`

**Step 1: Replace step_definitions in everyday_council**

Replace the current 4 steps with all 8:

```elixir
step_definitions: [
  # 1. Journal Intake — auto-categorize webhook drops into lodge cards
  %{
    name: "Journal Intake Step",
    description:
      "Drop a link, note, doc, or thought. Auto-categorize into a typed lodge card (note, checklist, link, todo). Extract key facts, tag for retrieval.",
    status: "active",
    trigger: "source",
    schedule: nil,
    roster: [
      %{
        "who" => "apprentice",
        "preferred_who" => "journal-keeper",
        "when" => "on_trigger",
        "how" => "solo"
      }
    ],
    source_ids: [],
    output_type: "lodge_card",
    lore_tags: ["journal", "intake"]
  },
  # 2. News Digest — synthesize feed items into tagged lore
  %{
    name: "News Digest Step",
    description:
      "Synthesize incoming feed articles into a clean lore entry. Tag by domain: tech, business, sports, culture, science. Be concise — extract signal, skip filler.",
    status: "active",
    trigger: "source",
    schedule: nil,
    roster: [
      %{
        "who" => "apprentice",
        "preferred_who" => "news-correspondent",
        "when" => "on_trigger",
        "how" => "solo"
      }
    ],
    source_ids: [],
    output_type: "artifact",
    write_mode: "append",
    entry_title_template: "News Digest — {date}",
    lore_tags: ["news", "digest"]
  },
  # 3. Morning Briefing — 8am daily
  %{
    name: "Morning Briefing Step",
    description:
      "Morning briefing. Synthesize overnight news across all domains (tech, business, sports, culture, science). Surface any pending todos or urgent lodge cards. Lead with the single most important thing. End with today's outlook. Write as a concise, readable morning brief.",
    status: "active",
    trigger: "scheduled",
    schedule: "0 8 * * *",
    roster: [
      %{
        "who" => "journeyman",
        "preferred_who" => "news-correspondent",
        "when" => "on_trigger",
        "how" => "solo"
      }
    ],
    source_ids: [],
    output_type: "lodge_card",
    context_providers: [
      %{"type" => "lore", "tags" => ["news", "digest"], "limit" => 20, "sort" => "newest"},
      %{"type" => "lore", "tags" => ["journal"], "limit" => 5, "sort" => "newest"}
    ],
    lore_tags: ["briefing", "morning"]
  },
  # 4. Midday Pulse — noon check-in
  %{
    name: "Midday Pulse Step",
    description:
      "Midday check-in. Anything urgent that came in since morning? Any breaking news? Quick status on todos. Keep it short — 3-4 bullet points max.",
    status: "active",
    trigger: "scheduled",
    schedule: "0 12 * * *",
    roster: [
      %{
        "who" => "apprentice",
        "preferred_who" => "life-coach",
        "when" => "on_trigger",
        "how" => "solo"
      }
    ],
    source_ids: [],
    output_type: "lodge_card",
    context_providers: [
      %{"type" => "lore", "tags" => ["news"], "limit" => 10, "sort" => "newest"},
      %{"type" => "lore", "tags" => ["journal"], "limit" => 3, "sort" => "newest"}
    ],
    lore_tags: ["briefing", "midday"]
  },
  # 5. Evening Debrief — 9pm wrap-up
  %{
    name: "Evening Debrief Step",
    description:
      "End-of-day debrief. Summarize what happened today across all domains. What was the day's biggest story? What got done? What's tomorrow looking like? Tone: reflective, concise.",
    status: "active",
    trigger: "scheduled",
    schedule: "0 21 * * *",
    roster: [
      %{
        "who" => "journeyman",
        "preferred_who" => "life-coach",
        "when" => "on_trigger",
        "how" => "solo"
      }
    ],
    source_ids: [],
    output_type: "lodge_card",
    context_providers: [
      %{"type" => "lore", "tags" => ["briefing"], "limit" => 3, "sort" => "newest"},
      %{"type" => "lore", "tags" => ["news"], "limit" => 15, "sort" => "newest"},
      %{"type" => "lore", "tags" => ["journal"], "limit" => 5, "sort" => "newest"}
    ],
    lore_tags: ["briefing", "evening"]
  },
  # 6. Todo Processor — lodge trigger on todo cards
  %{
    name: "Todo Processor Step",
    description:
      "When a todo card appears on the lodge, break it into actionable sub-steps. Add context from prior lore if relevant. Output as a structured grimoire entry with the tag 'actionable'.",
    status: "active",
    trigger: "manual",
    schedule: nil,
    roster: [
      %{
        "who" => "apprentice",
        "preferred_who" => "life-coach",
        "when" => "on_trigger",
        "how" => "solo"
      }
    ],
    source_ids: [],
    output_type: "artifact",
    write_mode: "append",
    entry_title_template: "Action Plan — {date}",
    context_providers: [
      %{"type" => "lore", "limit" => 5, "sort" => "newest"}
    ],
    lore_tags: ["actionable", "todo"]
  },
  # 7. Weekly Reflection — Monday 9am
  %{
    name: "Weekly Reflection Step",
    description:
      "Weekly reflection. Review the full week: news trends, journal entries, completed todos, patterns. What themes emerged? What shifted? What deserves more attention next week? Write as an augury — forward-looking synthesis.",
    status: "active",
    trigger: "scheduled",
    schedule: "0 9 * * 1",
    roster: [
      %{
        "who" => "journeyman",
        "preferred_who" => "life-coach",
        "when" => "on_trigger",
        "how" => "solo"
      }
    ],
    source_ids: [],
    output_type: "lodge_card",
    context_providers: [
      %{"type" => "lore", "limit" => 40, "sort" => "newest"}
    ],
    lore_tags: ["reflection", "weekly"]
  },
  # 8. Monthly Review — 1st of month 9am
  %{
    name: "Monthly Review Step",
    description:
      "Monthly review. Big picture: what changed this month, what trends are emerging across all domains, what priorities need adjusting. Review weekly reflections for patterns. Output as an augury with clear forward-looking guidance.",
    status: "active",
    trigger: "scheduled",
    schedule: "0 9 1 * *",
    roster: [
      %{
        "who" => "master",
        "preferred_who" => "life-coach",
        "when" => "on_trigger",
        "how" => "solo"
      }
    ],
    source_ids: [],
    output_type: "lodge_card",
    context_providers: [
      %{"type" => "lore", "tags" => ["reflection", "weekly"], "limit" => 5, "sort" => "newest"},
      %{"type" => "lore", "limit" => 20, "sort" => "top"}
    ],
    lore_tags: ["review", "monthly"]
  }
],
```

**Step 2: Compile**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors 2>&1 | tail -5' --pane=main:1.3`

**Step 3: Commit**

```bash
git add lib/ex_cortex/board/lifestyle.ex
git commit -m "feat: rebuild Everyday Council with 8 steps — briefings, intake, reflection, review"
```

---

### Task 8: Rebuild Everyday Council — Quests and Member Recruitment

**Files:**
- Modify: `lib/ex_cortex/board/lifestyle.ex`

**Step 1: Update quest_definition**

Replace the quest_definition with multiple quests. Since the Board struct only supports one `quest_definition`, we'll make the main quest the intake loop and add the briefing/reflection steps as standalone scheduled steps (they fire on their own schedules):

```elixir
quest_definition: %{
  name: "Everyday Council Quest",
  description:
    "Life OS intake loop. Processes incoming webhook drops and news feeds. Briefings, reflections, and reviews run on their own schedules.",
  status: "active",
  trigger: "source",
  schedule: nil,
  steps: [
    %{"step_name" => "Journal Intake Step", "flow" => "always"},
    %{"step_name" => "News Digest Step", "flow" => "always"}
  ],
  source_ids: []
}
```

Note: The scheduled steps (Morning Briefing, Midday Pulse, Evening Debrief, Weekly Reflection, Monthly Review) and the Todo Processor fire independently via ScheduledQuestRunner and a separate lodge-triggered quest. We need to create those quests too.

**Step 2: Add a helper to create additional quests on install**

The Board struct only supports one quest_definition. We need to add a post-install hook. Add a new field to the Board struct — `extra_quests: []` — and handle it in `Board.install/1`.

In `lib/ex_cortex/board.ex`, add to the defstruct:
```elixir
extra_quests: []
```

In `Board.install/1`, after the main quest creation (around line 141), add:

```elixir
Enum.each(template.extra_quests || [], fn quest_def ->
  quest_steps =
    (quest_def.steps || [])
    |> Enum.map(fn step ->
      %{"step_id" => Map.get(step_by_name, step["step_name"]), "flow" => step["flow"]}
    end)
    |> Enum.reject(fn step -> is_nil(step["step_id"]) end)

  case ExCortex.Quests.create_quest(Map.put(quest_def, :steps, quest_steps)) do
    {:ok, _} -> :ok
    {:error, changeset} ->
      if Enum.any?(changeset.errors, fn {field, {_, opts}} ->
           field == :name && opts[:constraint] == :unique
         end) do
        Logger.debug("[Board] Quest already exists: #{quest_def.name}")
      else
        Logger.warning("[Board] Failed to create quest #{quest_def.name}: #{inspect(changeset_errors(changeset))}")
      end
  end
end)
```

**Step 3: Add extra_quests to Everyday Council**

In the everyday_council template, add:

```elixir
extra_quests: [
  %{
    name: "Daily Briefings Quest",
    description: "Morning, midday, and evening briefings posted to the Lodge.",
    status: "active",
    trigger: "scheduled",
    schedule: "0 8 * * *",
    steps: [
      %{"step_name" => "Morning Briefing Step", "flow" => "always"},
      %{"step_name" => "Midday Pulse Step", "flow" => "always"},
      %{"step_name" => "Evening Debrief Step", "flow" => "always"}
    ]
  },
  %{
    name: "Todo Processor Quest",
    description: "Automatically processes new todo cards into actionable plans.",
    status: "active",
    trigger: "lodge",
    lodge_trigger_types: ["todo"],
    steps: [
      %{"step_name" => "Todo Processor Step", "flow" => "always"}
    ]
  },
  %{
    name: "Weekly Reflection Quest",
    description: "Monday morning week-in-review synthesis.",
    status: "active",
    trigger: "scheduled",
    schedule: "0 9 * * 1",
    steps: [
      %{"step_name" => "Weekly Reflection Step", "flow" => "always"}
    ]
  },
  %{
    name: "Monthly Review Quest",
    description: "First-of-month big picture review.",
    status: "active",
    trigger: "scheduled",
    schedule: "0 9 1 * *",
    steps: [
      %{"step_name" => "Monthly Review Step", "flow" => "always"}
    ]
  }
],
```

**Step 4: Update suggested_team**

Update the suggested_team to list all life_use member names so `auto_recruit_members` finds them:

```elixir
suggested_team: "life-coach, journal-keeper, news-correspondent, market-analyst, sports-anchor, science-correspondent",
```

**Step 5: Update description**

```elixir
description:
  "Your personal Jarvis. One install gets you: 12 news feeds across tech, business, sports, culture, and science. Auto-intake for anything you drop in. Morning, midday, and evening briefings on your Lodge. Todo processing. Weekly reflection and monthly review. All members auto-recruited.",
```

**Step 6: Compile and run tests**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors && mix test 2>&1 | tail -10' --pane=main:1.3`

**Step 7: Commit**

```bash
git add lib/ex_cortex/board.ex lib/ex_cortex/board/lifestyle.ex
git commit -m "feat: Everyday Council Jarvis mode — extra_quests, member recruitment, full description"
```

---

### Task 9: Full Integration Test

**Files:**
- Run full test suite, verify compilation, format

**Step 1: Format**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix format' --pane=main:1.3`

**Step 2: Compile with warnings-as-errors**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors 2>&1 | tail -10' --pane=main:1.3`

**Step 3: Run full test suite**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test 2>&1 | tail -10' --pane=main:1.3`

**Step 4: Fix any issues**

If there are failures, fix them and re-run.

**Step 5: Commit any format/fix changes**

```bash
git add -A
git commit -m "chore: format and fix integration issues"
```
