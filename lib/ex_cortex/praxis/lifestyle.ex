defmodule ExCortex.Praxis.Lifestyle do
  @moduledoc "Life-use cluster praxis templates for digest-driven and advisory workflows."

  alias ExCortex.Praxis

  def templates do
    [
      # Only everyday_council remains — the 5 digest-style templates
      # (tech_dispatch, sports_corner, market_signals, culture_desk, science_watch)
      # are now handled by digest reflexes with lobe-shaped pipelines.
      everyday_council()
    ]
  end

  defp everyday_council do
    %Praxis{
      id: "everyday_council",
      lobe: :limbic,
      name: "Everyday Council",
      category: :lifestyle,
      description:
        "Your personal Jarvis. One install gets you: 12 news feeds across tech, business, sports, culture, and science. Auto-intake for anything you drop in. Morning, midday, and evening briefings on your Cortex. Todo processing. Weekly reflection and monthly review. All neurons auto-recruited.",
      suggested_team:
        "life-coach, journal-keeper, news-correspondent, market-analyst, sports-anchor, science-correspondent",
      requires: [:any_members],
      source_definitions: [
        %{
          name: "Personal Inbox Webhook",
          source_type: "webhook",
          config: %{"secret" => ""}
        },
        %{
          name: "Hacker News",
          source_type: "feed",
          config: %{"url" => "https://news.ycombinator.com/rss", "interval" => 1_800_000},
          reflex_id: "hacker_news_rss"
        },
        %{
          name: "The Verge",
          source_type: "feed",
          config: %{"url" => "https://www.theverge.com/rss/index.xml", "interval" => 1_800_000},
          reflex_id: "the_verge_rss"
        },
        %{
          name: "Ars Technica",
          source_type: "feed",
          config: %{
            "url" => "https://feeds.arstechnica.com/arstechnica/index",
            "interval" => 1_800_000
          },
          reflex_id: "ars_technica_rss"
        },
        %{
          name: "Reuters Business",
          source_type: "feed",
          config: %{
            "url" => "https://feeds.reuters.com/reuters/businessNews",
            "interval" => 1_800_000
          },
          reflex_id: "reuters_business_rss"
        },
        %{
          name: "Financial Times",
          source_type: "feed",
          config: %{"url" => "https://www.ft.com/rss/home", "interval" => 1_800_000},
          reflex_id: "ft_rss"
        },
        %{
          name: "ESPN",
          source_type: "feed",
          config: %{"url" => "https://www.espn.com/espn/rss/news", "interval" => 1_800_000},
          reflex_id: "espn_rss"
        },
        %{
          name: "BBC Sport",
          source_type: "feed",
          config: %{
            "url" => "http://feeds.bbci.co.uk/sport/rss.xml",
            "interval" => 1_800_000
          },
          reflex_id: "bbc_sport_rss"
        },
        %{
          name: "Pitchfork",
          source_type: "feed",
          config: %{"url" => "https://pitchfork.com/rss/news/", "interval" => 3_600_000},
          reflex_id: "pitchfork_rss"
        },
        %{
          name: "AV Club",
          source_type: "feed",
          config: %{"url" => "https://www.avclub.com/rss", "interval" => 3_600_000},
          reflex_id: "av_club_rss"
        },
        %{
          name: "Science Daily",
          source_type: "feed",
          config: %{
            "url" => "https://www.sciencedaily.com/rss/all.xml",
            "interval" => 3_600_000
          },
          reflex_id: "science_daily_rss"
        },
        %{
          name: "Nature News",
          source_type: "feed",
          config: %{"url" => "https://www.nature.com/nature.rss", "interval" => 3_600_000},
          reflex_id: "nature_news_rss"
        }
      ],
      step_definitions: [
        %{
          name: "Journal Intake Step",
          description:
            "Drop a link, note, doc, or thought. Auto-categorize into a typed signal card (note, checklist, link, todo). Extract key facts, tag for retrieval.",
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
          output_type: "signal",
          engram_tags: ["journal", "intake"]
        },
        %{
          name: "News Digest Step",
          description:
            "Synthesize incoming feed articles into a clean engram. Tag by domain: tech, business, sports, culture, science. Be concise — extract signal, skip filler.",
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
          engram_tags: ["news", "digest"]
        },
        %{
          name: "Morning Briefing Step",
          description:
            "Morning briefing. Synthesize overnight news across all domains (tech, business, sports, culture, science). Surface any pending todos or urgent signal cards. Lead with the single most important thing. End with today's outlook. Write as a concise, readable morning brief.",
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
          output_type: "signal",
          context_providers: [
            %{"type" => "memory", "tags" => ["news", "digest"], "limit" => 20, "sort" => "newest"},
            %{"type" => "memory", "tags" => ["journal"], "limit" => 5, "sort" => "newest"}
          ],
          engram_tags: ["briefing", "morning"]
        },
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
          output_type: "signal",
          context_providers: [
            %{"type" => "memory", "tags" => ["news"], "limit" => 10, "sort" => "newest"},
            %{"type" => "memory", "tags" => ["journal"], "limit" => 3, "sort" => "newest"}
          ],
          engram_tags: ["briefing", "midday"]
        },
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
          output_type: "signal",
          context_providers: [
            %{"type" => "memory", "tags" => ["briefing"], "limit" => 3, "sort" => "newest"},
            %{"type" => "memory", "tags" => ["news"], "limit" => 15, "sort" => "newest"},
            %{"type" => "memory", "tags" => ["journal"], "limit" => 5, "sort" => "newest"}
          ],
          engram_tags: ["briefing", "evening"]
        },
        %{
          name: "Todo Processor Step",
          description:
            "When a todo card appears on the cortex, break it into actionable sub-steps. Add context from prior memory if relevant. Output as a structured memory entry with the tag 'actionable'.",
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
            %{"type" => "memory", "limit" => 5, "sort" => "newest"}
          ],
          engram_tags: ["actionable", "todo"]
        },
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
          output_type: "signal",
          context_providers: [
            %{"type" => "memory", "limit" => 40, "sort" => "newest"}
          ],
          engram_tags: ["reflection", "weekly"]
        },
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
          output_type: "signal",
          context_providers: [
            %{
              "type" => "memory",
              "tags" => ["reflection", "weekly"],
              "limit" => 5,
              "sort" => "newest"
            },
            %{"type" => "memory", "limit" => 20, "sort" => "top"}
          ],
          engram_tags: ["review", "monthly"]
        }
      ],
      rumination_definition: %{
        name: "Everyday Council Thought",
        description: "Life OS intake loop. Processes incoming webhook drops and news feeds.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Journal Intake Step", "flow" => "always"},
          %{"step_name" => "News Digest Step", "flow" => "always"}
        ],
        source_ids: []
      },
      extra_ruminations: [
        %{
          name: "Daily Briefings Thought",
          description: "Morning, midday, and evening briefings posted to the Cortex.",
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
          name: "Todo Processor Thought",
          description: "Automatically processes new todo cards into actionable plans.",
          status: "active",
          trigger: "cortex",
          signal_trigger_types: ["todo"],
          steps: [
            %{"step_name" => "Todo Processor Step", "flow" => "always"}
          ]
        },
        %{
          name: "Weekly Reflection Thought",
          description: "Monday morning week-in-review synthesis.",
          status: "active",
          trigger: "scheduled",
          schedule: "0 9 * * 1",
          steps: [
            %{"step_name" => "Weekly Reflection Step", "flow" => "always"}
          ]
        },
        %{
          name: "Monthly Review Thought",
          description: "First-of-month big picture review.",
          status: "active",
          trigger: "scheduled",
          schedule: "0 9 1 * *",
          steps: [
            %{"step_name" => "Monthly Review Step", "flow" => "always"}
          ]
        }
      ]
    }
  end

end
