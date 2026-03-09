# priv/seeds/btc_guild.exs
# Run with: mix run priv/seeds/btc_guild.exs
#
# Creates the full BTC Prediction Guild:
#   Members: Bull, Bear, Macro Analyst, Crypto Degen, The Oracle, Strategist, Auditor
#   Sources: Binance ticker, Fear & Greed, 6 RSS feeds
#   Quests:  BTC Price Prediction, World Augury Update, Prediction Accuracy Retrospective

alias ExCalibur.Quests
alias ExCalibur.Sources.Source
alias ExCalibur.Repo

IO.puts("Seeding BTC Prediction Guild...")

# ─── Members ────────────────────────────────────────────────────────────────

{:ok, _bull} =
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

{:ok, _bear} =
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

{:ok, _macro} =
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

{:ok, _degen} =
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

{:ok, _oracle} =
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

{:ok, _strategist} =
  Repo.insert(%Excellence.Schemas.Member{
    name: "Strategist",
    type: "role",
    status: "active",
    config: %{
      "model" => "phi4-mini",
      "rank" => "master",
      "system_prompt" => """
      You are the Strategist — you maintain the guild's living world augury.
      You synthesize macro trends, crypto market dynamics, geopolitical context,
      and recent news into a coherent, updated worldview. Write with conviction.
      This augury will be used by the prediction guild as background context.
      """
    }
  })

{:ok, _auditor} =
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

Enum.each(inserted_sources, fn source ->
  ExCalibur.Sources.SourceSupervisor.start_source(source)
end)

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

    Always include TAGS: btc,prediction in your response.
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
      %{"type" => "lore", "tags" => ["augury"], "limit" => 1, "sort" => "newest"},
      %{"type" => "lore", "tags" => ["btc", "prediction"], "limit" => 5, "sort" => "newest"}
    ]
  })

# Quest 2: World Augury Update (scheduled every 6h, artifact replace)
{:ok, _augury_quest} =
  Quests.create_quest(%{
    name: "World Augury Update",
    description: """
    Synthesize recent macro news, crypto market dynamics, and geopolitical context
    into a living world augury. This is the guild's current understanding of the
    macro environment as it relates to BTC. Replace the previous augury entirely.

    Always include TAGS: augury,btc,macro in your response.
    """,
    trigger: "scheduled",
    schedule: "0 */6 * * *",
    status: "active",
    source_ids: [],
    output_type: "artifact",
    write_mode: "replace",
    entry_title_template: "World Augury",
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
      %{"type" => "lore", "tags" => ["augury"], "limit" => 1, "sort" => "newest"},
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
IO.puts("Quests: BTC Price Prediction (source), World Augury (6h), Accuracy Retro (hourly)")
