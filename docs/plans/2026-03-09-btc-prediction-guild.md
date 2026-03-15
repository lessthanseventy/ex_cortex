# BTC Prediction Guild Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A multi-perspective BTC price prediction guild where Bull, Bear, Macro Analyst, and Crypto Degen members debate in parallel, then The Oracle synthesizes a 15-minute price prediction, with a living World Thesis and hourly accuracy retrospectives — all written to the grimoire.

**Architecture:** Eight sources (Binance ticker, Fear & Greed, 6 RSS feeds) trigger a prediction quest. QuestRunner is extended to thread step outputs forward so the Oracle sees all prior members' reasoning. Two scheduled quests run hourly (accuracy retrospective) and every 6 hours (world thesis update). Everything seeded via a single script.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto, Ollama (local LLM), PostgreSQL, existing SourceWorker + QuestRunner + Lore system.

---

### Task 1: Extend QuestRunner to thread step outputs forward

The Oracle needs to see Bull/Bear/Macro/Degen's full reasoning. Currently `run_artifact/2` only uses the first member of the first roster step. We need multi-step artifact quests to run all steps except the last in "reasoning mode" and pass their outputs to the final synthesizer step.

**Files:**
- Modify: `lib/ex_cortex/quest_runner.ex`

**Step 1: Read the current `run_artifact/2` function**

It's at line 284. Understand: it grabs first member of first roster step, calls LLM with artifact system prompt, parses result.

**Step 2: Modify `run_artifact/2` to support multi-step threading**

Replace the existing `run_artifact/2` with this version:

```elixir
defp run_artifact(quest, input_text) do
  ollama_url = Application.get_env(:ex_cortex, :ollama_url, "http://127.0.0.1:11434")
  ollama = Ollama.new(base_url: ollama_url)

  roster = quest.roster || []

  case roster do
    [] ->
      {:error, :no_roster}

    [single_step] ->
      # Single step — original behaviour
      run_artifact_step(single_step, input_text, quest, ollama)

    steps ->
      # Multi-step: run all but last in reasoning mode, thread outputs to final step
      {prelim_steps, [final_step]} = Enum.split(steps, length(steps) - 1)

      reasoning_context =
        Enum.map_join(prelim_steps, "\n\n", fn step ->
          members = resolve_members(step)
          label = step["label"] || step["who"] || "Analyst"

          member_outputs =
            Enum.map_join(members, "\n\n", fn member ->
              reasoning_prompt = reasoning_system_prompt(member, step)

              messages = [
                %{role: :system, content: reasoning_prompt},
                %{role: :user, content: input_text}
              ]

              text =
                case member do
                  %{type: :claude, tier: tier} ->
                    case ClaudeClient.complete(tier, reasoning_prompt, input_text) do
                      {:ok, t} -> t
                      _ -> "(no response)"
                    end

                  %{type: :ollama, model: model} ->
                    case Ollama.chat(ollama, model, messages) do
                      {:ok, %{content: t}} -> t
                      {:ok, t} when is_binary(t) -> t
                      _ -> "(no response)"
                    end
                end

              "**#{member.name}:** #{text}"
            end)

          "### #{label}\n#{member_outputs}"
        end)

      augmented = "#{input_text}\n\n---\n## Team Analysis\n#{reasoning_context}"
      run_artifact_step(final_step, augmented, quest, ollama)
  end
end

defp run_artifact_step(step, input_text, quest, ollama) do
  members = resolve_members(step)
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

defp reasoning_system_prompt(member, step) do
  base = member.system_prompt || ""
  label = step["label"] || member.name

  """
  #{base}

  You are #{label}. Provide your analysis and perspective on the data below.
  Be direct and opinionated. Your output will be read by a synthesizer.
  Do NOT use the TITLE/IMPORTANCE/TAGS/BODY format — just write your raw analysis.
  """
end
```

**Step 3: Remove the old `run_artifact/2` function body**

Delete lines 284–331 (the old implementation). The new multi-clause version above replaces it.

**Step 4: Compile and check for warnings**

```bash
cd /home/andrew/projects/ex_cortex && mix compile 2>&1 | grep -E "(warning|error)"
```

Expected: no output (no warnings, no errors)

**Step 5: Commit**

```bash
git add lib/ex_cortex/quest_runner.ex
git commit -m "feat: thread step outputs to Oracle in multi-step artifact quests"
```

---

### Task 2: Create the seed script

One script that creates all 5 members, 8 sources, and 3 quests. Run it on a clean DB to get the full guild running instantly.

**Files:**
- Create: `priv/seeds/btc_guild.exs`

**Step 1: Write the seed script**

```elixir
# priv/seeds/btc_guild.exs
# Run with: mix run priv/seeds/btc_guild.exs
#
# Creates the full BTC Prediction Guild:
#   Members: Bull, Bear, Macro Analyst, Crypto Degen, The Oracle, Strategist, Auditor
#   Sources: Binance ticker, Fear & Greed, 6 RSS feeds
#   Quests:  BTC Price Prediction, World Thesis Update, Prediction Accuracy Retrospective

alias ExCortex.Quests
alias ExCortex.Sources.Source
alias ExCortex.Repo
import Ecto.Query

IO.puts("Seeding BTC Prediction Guild...")

# ─── Members ────────────────────────────────────────────────────────────────

{:ok, bull} =
  Repo.insert(%Excellence.Schemas.Member{
    name: "Bull",
    type: "role",
    status: "active",
    config: %{
      "model" => "phi4-mini",
      "rank" => "apprentice",
      "system_prompt" => """
      You are Bull — an aggressive crypto optimist.
      You look for upside signals: momentum, institutional inflows, bullish technicals,
      positive news catalysts, FOMO cycles, support levels holding.
      You always find reasons the price will go up. Be specific with price reasoning.
      """
    }
  })

{:ok, bear} =
  Repo.insert(%Excellence.Schemas.Member{
    name: "Bear",
    type: "role",
    status: "active",
    config: %{
      "model" => "phi4-mini",
      "rank" => "apprentice",
      "system_prompt" => """
      You are Bear — a cautious crypto skeptic.
      You look for downside risks: overextension, bad macro, regulatory threats,
      whale selling, liquidation cascades, resistance levels, fear spikes.
      You always find reasons the price will go down. Be specific with price reasoning.
      """
    }
  })

{:ok, macro} =
  Repo.insert(%Excellence.Schemas.Member{
    name: "Macro Analyst",
    type: "role",
    status: "active",
    config: %{
      "model" => "phi4-mini",
      "rank" => "journeyman",
      "system_prompt" => """
      You are the Macro Analyst — you read world events through a BTC lens.
      You focus on: DXY strength/weakness, rate expectations, geopolitical risk,
      equities correlation, inflation data, and broader risk-on/risk-off sentiment.
      Translate macro context into a directional BTC view for the next 15 minutes.
      """
    }
  })

{:ok, degen} =
  Repo.insert(%Excellence.Schemas.Member{
    name: "Crypto Degen",
    type: "role",
    status: "active",
    config: %{
      "model" => "phi4-mini",
      "rank" => "journeyman",
      "system_prompt" => """
      You are Crypto Degen — vibes-based crypto trader.
      You focus on: social sentiment, Fear & Greed index, Twitter/X energy,
      whale wallet moves, funding rates, open interest, and gut feel.
      Be irreverent. Give a raw take on where BTC is going in the next 15 minutes.
      """
    }
  })

{:ok, oracle} =
  Repo.insert(%Excellence.Schemas.Member{
    name: "The Oracle",
    type: "role",
    status: "active",
    config: %{
      "model" => "phi4-mini",
      "rank" => "master",
      "system_prompt" => """
      You are The Oracle — the final synthesizer for BTC price predictions.
      You receive the current market data AND the analysis from Bull, Bear,
      Macro Analyst, and Crypto Degen. Weigh all perspectives and make a
      definitive 15-minute price prediction. Be specific: give a target price
      and confidence level.
      """
    }
  })

{:ok, strategist} =
  Repo.insert(%Excellence.Schemas.Member{
    name: "Strategist",
    type: "role",
    status: "active",
    config: %{
      "model" => "phi4-mini",
      "rank" => "master",
      "system_prompt" => """
      You are the Strategist — you maintain the guild's living world thesis.
      You synthesize macro trends, crypto market dynamics, geopolitical context,
      and recent news into a coherent, updated worldview. Write with conviction.
      This thesis will be used by the prediction guild as background context.
      """
    }
  })

{:ok, auditor} =
  Repo.insert(%Excellence.Schemas.Member{
    name: "Auditor",
    type: "role",
    status: "active",
    config: %{
      "model" => "phi4-mini",
      "rank" => "master",
      "system_prompt" => """
      You are the Auditor — you evaluate the prediction guild's accuracy.
      You receive recent predictions and current market data. Calculate hit rate,
      average error, and identify patterns in when the guild is right or wrong.
      Be analytical and honest. Produce a clear scorecard.
      """
    }
  })

IO.puts("  ✓ Created 7 members")

# ─── Sources ────────────────────────────────────────────────────────────────

sources = [
  %{
    source_type: "url",
    status: "active",
    config: %{
      "url" => "https://api.binance.com/api/v3/ticker/24hr?symbol=BTCUSDT",
      "interval" => 300_000,
      "label" => "Binance BTC/USDT ticker"
    }
  },
  %{
    source_type: "url",
    status: "active",
    config: %{
      "url" => "https://api.alternative.me/fng/",
      "interval" => 900_000,
      "label" => "Fear & Greed Index"
    }
  },
  %{
    source_type: "feed",
    status: "active",
    config: %{
      "url" => "https://feeds.feedburner.com/CoinDesk",
      "interval" => 900_000,
      "label" => "CoinDesk"
    }
  },
  %{
    source_type: "feed",
    status: "active",
    config: %{
      "url" => "https://cointelegraph.com/rss",
      "interval" => 900_000,
      "label" => "CoinTelegraph"
    }
  },
  %{
    source_type: "feed",
    status: "active",
    config: %{
      "url" => "https://feeds.reuters.com/reuters/businessNews",
      "interval" => 1_800_000,
      "label" => "Reuters Business"
    }
  },
  %{
    source_type: "feed",
    status: "active",
    config: %{
      "url" => "https://hnrss.org/newest?q=bitcoin+crypto+markets",
      "interval" => 1_800_000,
      "label" => "Hacker News BTC/Crypto"
    }
  },
  %{
    source_type: "feed",
    status: "active",
    config: %{
      "url" => "https://www.ft.com/rss/home",
      "interval" => 3_600_000,
      "label" => "Financial Times"
    }
  },
  %{
    source_type: "feed",
    status: "active",
    config: %{
      "url" => "https://www.coindesk.com/arc/outboundfeeds/rss/",
      "interval" => 900_000,
      "label" => "CoinDesk (alt)"
    }
  }
]

inserted_sources =
  Enum.map(sources, fn attrs ->
    {:ok, source} = %Source{} |> Source.changeset(attrs) |> Repo.insert()
    source
  end)

source_ids = Enum.map(inserted_sources, &to_string(&1.id))
IO.puts("  ✓ Created #{length(inserted_sources)} sources")

# ─── Quests ─────────────────────────────────────────────────────────────────

# Quest 1: BTC Price Prediction (source-triggered, artifact → grimoire)
{:ok, _prediction_quest} =
  Quests.create_quest(%{
    name: "BTC Price Prediction",
    description: """
    Synthesize current BTC market data and news context into a 15-minute price prediction.
    Weigh input from Bull, Bear, Macro Analyst, and Crypto Degen perspectives.
    Produce a structured prediction with target price, confidence, and reasoning.
    """,
    trigger: "source",
    status: "active",
    source_ids: source_ids,
    output_type: "artifact",
    write_mode: "append",
    entry_title_template: "BTC Prediction — {date}",
    roster: [
      %{
        "who" => "apprentice",
        "how" => "solo",
        "when" => "parallel",
        "label" => "Apprentice Analysts (Bull & Bear)"
      },
      %{
        "who" => "journeyman",
        "how" => "solo",
        "when" => "parallel",
        "label" => "Journeyman Analysts (Macro & Degen)"
      },
      %{
        "preferred_who" => "The Oracle",
        "who" => "master",
        "how" => "solo",
        "when" => "sequential",
        "label" => "The Oracle (Synthesizer)"
      }
    ],
    context_providers: [
      %{"type" => "lore", "tags" => ["thesis"], "limit" => 1, "sort" => "newest"},
      %{"type" => "lore", "tags" => ["btc", "prediction"], "limit" => 5, "sort" => "newest"}
    ]
  })

# Quest 2: World Thesis Update (scheduled every 6h, artifact replace)
{:ok, _thesis_quest} =
  Quests.create_quest(%{
    name: "World Thesis Update",
    description: """
    Synthesize recent macro news, crypto market dynamics, and geopolitical context
    into a living world thesis. This is the guild's current understanding of the
    macro environment as it relates to BTC. Replace the previous thesis entirely.
    """,
    trigger: "scheduled",
    schedule: "0 */6 * * *",
    status: "active",
    source_ids: [],
    output_type: "artifact",
    write_mode: "replace",
    entry_title_template: "World Thesis",
    roster: [
      %{
        "preferred_who" => "Strategist",
        "who" => "master",
        "how" => "solo",
        "when" => "sequential",
        "label" => "Strategist"
      }
    ],
    context_providers: [
      %{"type" => "lore", "tags" => ["thesis"], "limit" => 1, "sort" => "newest"},
      %{"type" => "lore", "tags" => ["btc"], "limit" => 10, "sort" => "newest"}
    ]
  })

# Quest 3: Prediction Accuracy Retrospective (scheduled hourly, artifact append)
{:ok, _retro_quest} =
  Quests.create_quest(%{
    name: "Prediction Accuracy Retrospective",
    description: """
    Review the last 12 BTC price predictions and compare them against actual price
    movements. Calculate hit rate and average error. Identify patterns.
    Produce a scorecard artifact.
    """,
    trigger: "scheduled",
    schedule: "0 * * * *",
    status: "active",
    source_ids: [],
    output_type: "artifact",
    write_mode: "append",
    entry_title_template: "Prediction Scorecard — {date}",
    roster: [
      %{
        "preferred_who" => "Auditor",
        "who" => "master",
        "how" => "solo",
        "when" => "sequential",
        "label" => "Auditor"
      }
    ],
    context_providers: [
      %{"type" => "lore", "tags" => ["btc", "prediction"], "limit" => 12, "sort" => "newest"},
      %{"type" => "lore", "tags" => ["btc", "prediction"], "limit" => 1, "sort" => "importance"}
    ]
  })

IO.puts("  ✓ Created 3 quests")
IO.puts("")
IO.puts("BTC Prediction Guild seeded successfully!")
IO.puts("Members: Bull, Bear, Macro Analyst, Crypto Degen, The Oracle, Strategist, Auditor")
IO.puts("Sources: #{length(inserted_sources)} active (Binance, Fear&Greed, 6 RSS feeds)")
IO.puts("Quests: BTC Price Prediction (source), World Thesis (6h), Accuracy Retro (hourly)")
```

**Step 2: Run the seed script against the Docker DB**

```bash
cd /home/andrew/projects/ex_cortex && DATABASE_URL="ecto://excellence:excellence@localhost:5433/ex_cortex" mix run priv/seeds/btc_guild.exs
```

Expected output:
```
Seeding BTC Prediction Guild...
  ✓ Created 7 members
  ✓ Created 8 sources
  ✓ Created 3 quests

BTC Prediction Guild seeded successfully!
```

**Step 3: Verify in the DB**

```bash
PGPASSWORD=excellence psql -h localhost -p 5433 -U excellence -d ex_cortex -c \
  "SELECT name, type, status FROM excellence_members WHERE type='role';"
PGPASSWORD=excellence psql -h localhost -p 5433 -U excellence -d ex_cortex -c \
  "SELECT name, trigger, output_type FROM excellence_quests;"
PGPASSWORD=excellence psql -h localhost -p 5433 -U excellence -d ex_cortex -c \
  "SELECT source_type, config->>'label' as label, status FROM excellence_sources;"
```

**Step 4: Commit**

```bash
git add priv/seeds/btc_guild.exs
git commit -m "feat: add BTC prediction guild seed script"
```

---

### Task 3: Fix lore entry write_mode for thesis (pinned, tag-based)

The World Thesis quest uses `write_mode: "replace"` but `Lore.write_artifact` replaces based on `quest_id`. The thesis should be findable by `tags: ["thesis"]`. Verify this works and the thesis entry gets the `thesis` tag in its artifact output.

**Files:**
- Modify: `lib/ex_cortex/quest_runner.ex` — `artifact_system_prompt/1`

**Step 1: Read `artifact_system_prompt/1`**

It's around line 333. It uses `quest.description` as the instruction.

**Step 2: Add thesis tag instruction to the World Thesis quest system prompt**

The Strategist's output needs to include `TAGS: thesis,btc` so the lore entry gets properly tagged. The `artifact_system_prompt` already instructs the format — the description on the quest will include the tag instruction.

The seed script's World Thesis quest description already says "Replace the previous thesis entirely." The TAGS line in the LLM output determines the grimoire tags. We need to ensure the Strategist is prompted to use `thesis` as a tag.

Add to the World Thesis quest description in the seed script:

```
Always include TAGS: thesis,btc,macro in your response.
```

**Step 3: Update the seed script description**

Edit `priv/seeds/btc_guild.exs`, change the World Thesis description to:

```elixir
description: """
Synthesize recent macro news, crypto market dynamics, and geopolitical context
into a living world thesis. This is the guild's current understanding of the
macro environment as it relates to BTC. Replace the previous thesis entirely.

Always include TAGS: thesis,btc,macro in your response.
""",
```

**Step 4: Similarly ensure prediction quest outputs btc,prediction tags**

Edit the BTC Price Prediction quest description:

```elixir
description: """
Synthesize current BTC market data and news context into a 15-minute price prediction.
Weigh input from Bull, Bear, Macro Analyst, and Crypto Degen perspectives.
Produce a structured prediction with target price, confidence, and reasoning.

Always include TAGS: btc,prediction in your response.
""",
```

**Step 5: Compile and verify**

```bash
cd /home/andrew/projects/ex_cortex && mix compile 2>&1 | grep -E "(warning|error)"
```

**Step 6: Commit**

```bash
git add priv/seeds/btc_guild.exs
git commit -m "feat: add tag instructions to guild quest descriptions"
```

---

### Task 4: End-to-end smoke test

Verify the full pipeline works: source fetches → quest runs → grimoire entry appears.

**Step 1: Restart the server to pick up code changes**

The server should hot-reload, but to be safe send Ctrl+C and restart:

```bash
# In tmux pane main:1.2, the server restarts automatically with mise run dev
# Or manually: tmux-cli send 'C-c' --pane=main:1.2 --key
```

**Step 2: Trigger a sync via the Library UI**

Open `http://localhost:4001/library` and click "Sync All". Watch server logs in pane main:1.2 for:

```
[info] [SourceWorker] Running quest X (BTC Price Prediction) for source Y
```

**Step 3: Watch for Ollama activity**

Ollama should receive multiple `/api/chat` calls — one per member (Bull, Bear, Macro, Degen, then Oracle).

**Step 4: Check the grimoire**

Open `http://localhost:4001/grimoire`. A "BTC Prediction" entry should appear within ~2 minutes of syncing.

**Step 5: Manually trigger the World Thesis quest**

In the Quests UI, find "World Thesis Update" and run it manually. A "World Thesis" entry should appear in the grimoire tagged `thesis,btc,macro`.

**Step 6: Commit if all working**

```bash
git add -p  # review any incidental changes
git commit -m "chore: verify BTC prediction guild e2e"
```

---

## Notes

- The Binance ticker returns JSON like `{"symbol":"BTCUSDT","lastPrice":"67432.50","priceChange":...}`. The URL source fetches the raw JSON as content — the LLMs can parse it.
- The Fear & Greed API returns `{"data":[{"value":"72","value_classification":"Greed",...}]}`.
- If a feed source returns no new items (deduplication), it won't trigger the quest. The Binance URL source always returns fresh data on every tick (no dedup).
- The `preferred_who` field in roster steps routes to a named member first, falling back to rank-based selection.
- `write_mode: "replace"` on the thesis quest replaces by `quest_id`. Since the thesis quest has a fixed ID, this will always keep exactly one thesis entry.
