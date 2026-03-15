defmodule ExCortex.Board.Lifestyle do
  @moduledoc "Life-use cluster board templates for digest-driven and advisory workflows."

  alias ExCortex.Board

  def templates do
    [
      everyday_council(),
      tech_dispatch(),
      sports_corner(),
      market_signals(),
      culture_desk(),
      science_watch()
    ]
  end

  defp everyday_council do
    %Board{
      id: "everyday_council",
      banner: :lifestyle,
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
      thought_definition: %{
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
      extra_thoughts: [
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

  defp tech_dispatch do
    %Board{
      id: "tech_dispatch",
      banner: :lifestyle,
      name: "Tech Dispatch",
      category: :lifestyle,
      description: "Daily and weekly technology news synthesis. Learns trends over time through accumulated memory.",
      suggested_team: "Tech Dispatch cluster is purpose-built for this.",
      requires: [:any_members, {:not_installed, "everyday_council"}],
      source_definitions: [
        %{
          name: "Hacker News",
          source_type: "feed",
          config: %{"url" => "https://news.ycombinator.com/rss", "interval" => 1_800_000},
          reflex_id: "hacker_news_rss"
        },
        %{
          name: "The Verge",
          source_type: "feed",
          config: %{
            "url" => "https://www.theverge.com/rss/index.xml",
            "interval" => 1_800_000
          },
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
        }
      ],
      step_definitions: [
        %{
          name: "Daily Tech Brief Step",
          description: "Synthesizes incoming tech articles into a clean daily briefing stored as memory.",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [
            %{
              "who" => "journeyman",
              "preferred_who" => "news-correspondent",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Tech Brief — {date}"
        },
        %{
          name: "Weekly Tech Trends Step",
          description: "Synthesizes the week's memory into trend patterns.",
          status: "active",
          trigger: "scheduled",
          schedule: "0 8 * * 1",
          roster: [
            %{
              "who" => "journeyman",
              "preferred_who" => "trend-spotter",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Weekly Tech Trends — {date}",
          context_providers: [%{"type" => "memory", "limit" => 30, "sort" => "newest"}]
        }
      ],
      thought_definition: %{
        name: "Tech Digest Loop Thought",
        description: "Continuous tech news intake and weekly trend synthesis.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Daily Tech Brief Step", "flow" => "always"},
          %{"step_name" => "Weekly Tech Trends Step", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp sports_corner do
    %Board{
      id: "sports_corner",
      banner: :lifestyle,
      name: "Sports Corner",
      category: :lifestyle,
      description: "Daily sports digest — scores, storylines, and what it all means. Builds a narrative arc over time.",
      suggested_team: "Sports Corner cluster is purpose-built for this.",
      requires: [:any_members, {:not_installed, "everyday_council"}],
      source_definitions: [
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
          name: "The Athletic",
          source_type: "feed",
          config: %{"url" => "https://theathletic.com/rss-feed/", "interval" => 1_800_000},
          reflex_id: "the_athletic_rss"
        }
      ],
      step_definitions: [
        %{
          name: "Daily Sports Digest Step",
          description: "Daily sports brief: scores, highlights, best storyline.",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [
            %{
              "who" => "journeyman",
              "preferred_who" => "sports-anchor",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Sports — {date}"
        },
        %{
          name: "Weekend Roundup Step",
          description: "End-of-week narrative synthesis from the week's sports memory.",
          status: "active",
          trigger: "scheduled",
          schedule: "0 10 * * 6",
          roster: [
            %{
              "who" => "apprentice",
              "preferred_who" => "the-historian",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "artifact",
          entry_title_template: "Weekend Roundup — {date}",
          context_providers: [%{"type" => "memory", "limit" => 10, "sort" => "newest"}]
        }
      ],
      thought_definition: %{
        name: "Sports Digest Loop Thought",
        description: "Continuous sports news intake and weekend narrative synthesis.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Daily Sports Digest Step", "flow" => "always"},
          %{"step_name" => "Weekend Roundup Step", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp market_signals do
    %Board{
      id: "market_signals",
      banner: :lifestyle,
      name: "Market Signals",
      category: :lifestyle,
      description:
        "Business and financial intelligence. Tracks market signals through daily synthesis and weekly pattern recognition.",
      suggested_team: "Market Signals cluster is purpose-built for this.",
      requires: [:any_members, {:not_installed, "everyday_council"}],
      source_definitions: [
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
        }
      ],
      step_definitions: [
        %{
          name: "Daily Market Brief Step",
          description: "Daily business and financial synthesis from incoming sources.",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [
            %{
              "who" => "journeyman",
              "preferred_who" => "market-analyst",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Market Brief — {date}"
        },
        %{
          name: "Weekly Market Roundup Step",
          description: "Weekly synthesis of market signals and emerging patterns.",
          status: "active",
          trigger: "scheduled",
          schedule: "0 7 * * 1",
          roster: [
            %{
              "who" => "all",
              "when" => "on_trigger",
              "how" => "consensus"
            }
          ],
          source_ids: [],
          output_type: "artifact",
          context_providers: [%{"type" => "memory", "limit" => 10, "sort" => "newest"}],
          entry_title_template: "Market Roundup — {date}"
        }
      ],
      thought_definition: %{
        name: "Market Digest Loop Thought",
        description: "Continuous market news intake and weekly pattern synthesis.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Daily Market Brief Step", "flow" => "always"},
          %{"step_name" => "Weekly Market Roundup Step", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp culture_desk do
    %Board{
      id: "culture_desk",
      banner: :lifestyle,
      name: "Culture Desk",
      category: :lifestyle,
      description: "Entertainment, music, film, culture. The tabloid voice meets the historian's memory.",
      suggested_team: "Culture Desk cluster is purpose-built for this.",
      requires: [:any_members, {:not_installed, "everyday_council"}],
      source_definitions: [
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
          name: "Vulture",
          source_type: "feed",
          config: %{"url" => "https://www.vulture.com/rss/all.xml", "interval" => 3_600_000},
          reflex_id: "vulture_rss"
        }
      ],
      step_definitions: [
        %{
          name: "Culture Brief Step",
          description: "Pop culture synthesis with tabloid flair — what's trending, what it means, what's overblown.",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [
            %{
              "who" => "journeyman",
              "preferred_who" => "the-tabloid",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Culture Brief — {date}",
          engram_tags: ["culture", "entertainment"]
        },
        %{
          name: "Weekly Arts Roundup Step",
          description: "Weekly synthesis of culture and entertainment.",
          status: "active",
          trigger: "scheduled",
          schedule: "0 10 * * 6",
          roster: [
            %{
              "who" => "apprentice",
              "preferred_who" => "the-historian",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "artifact",
          entry_title_template: "Arts Roundup — {date}",
          context_providers: [%{"type" => "memory", "limit" => 10, "sort" => "newest"}]
        }
      ],
      thought_definition: %{
        name: "Culture Digest Loop Thought",
        description: "Continuous culture intake and weekly arts synthesis.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Culture Brief Step", "flow" => "always"},
          %{"step_name" => "Weekly Arts Roundup Step", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp science_watch do
    %Board{
      id: "science_watch",
      banner: :lifestyle,
      name: "Science Watch",
      category: :lifestyle,
      description:
        "Research and discovery synthesis. Translates science into plain language, separates signal from hype.",
      suggested_team: "Science Watch cluster is purpose-built for this.",
      requires: [:any_members, {:not_installed, "everyday_council"}],
      source_definitions: [
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
        },
        %{
          name: "Ars Technica Science",
          source_type: "feed",
          config: %{
            "url" => "https://feeds.arstechnica.com/arstechnica/science",
            "interval" => 3_600_000
          },
          reflex_id: "ars_science_rss"
        }
      ],
      step_definitions: [
        %{
          name: "Daily Science Brief Step",
          description: "Plain-language synthesis of research and science news.",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [
            %{
              "who" => "journeyman",
              "preferred_who" => "science-correspondent",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Science Brief — {date}"
        },
        %{
          name: "Weekly Research Roundup Step",
          description: "Weekly synthesis of scientific developments.",
          status: "active",
          trigger: "scheduled",
          schedule: "0 9 * * 1",
          roster: [
            %{
              "who" => "apprentice",
              "preferred_who" => "the-historian",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "artifact",
          entry_title_template: "Research Roundup — {date}",
          context_providers: [%{"type" => "memory", "limit" => 20, "sort" => "newest"}]
        }
      ],
      thought_definition: %{
        name: "Science Digest Loop Thought",
        description: "Continuous science news intake and weekly research synthesis.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Daily Science Brief Step", "flow" => "always"},
          %{"step_name" => "Weekly Research Roundup Step", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end
end
