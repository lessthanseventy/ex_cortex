defmodule ExCalibur.Board.Lifestyle do
  @moduledoc "Life-use guild board templates for digest-driven and advisory workflows."

  alias ExCalibur.Board

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
      name: "Everyday Council",
      category: :lifestyle,
      description:
        "Your personal life OS. Daily briefings at 8am, noon, and 9pm. Automatic intake for links, notes, and thoughts. Weekly news digest, reflection, and monthly review. Advisory panel on demand for decisions, gut checks, and priority resets.",
      suggested_team: "Everyday Council guild is purpose-built for this.",
      requires: [:any_members],
      source_definitions: [
        %{
          name: "Personal Inbox Webhook",
          source_type: "webhook",
          config: %{"secret" => ""}
        }
      ],
      step_definitions: [
        %{
          name: "Life Decision Review Step",
          description:
            "Submit a decision or dilemma for a full panel review. Each member evaluates from their perspective.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: [],
          output_type: "verdict"
        },
        %{
          name: "Quick Take Step",
          description: "Fast advisory from a single grounded perspective.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{
              "who" => "journeyman",
              "preferred_who" => "life-coach",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "verdict"
        },
        %{
          name: "Journal Intake Step",
          description:
            "Drop a link, note, doc, or thought. The journal keeper processes it into a structured lore entry.",
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
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Journal — {date}"
        },
        %{
          name: "Weekly Reflection Step",
          description: "Weekly synthesis of accumulated journal entries into a reflection.",
          status: "active",
          trigger: "scheduled",
          schedule: "0 9 * * 1",
          roster: [
            %{
              "who" => "journeyman",
              "preferred_who" => "the-historian",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Weekly Reflection — {date}",
          context_providers: [%{"type" => "lore", "limit" => 20, "sort" => "newest"}]
        }
      ],
      quest_definition: %{
        name: "Everyday Council Quest",
        description: "Intake loop and weekly reflection for the Everyday Council.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Journal Intake Step", "flow" => "always"},
          %{"step_name" => "Weekly Reflection Step", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp tech_dispatch do
    %Board{
      id: "tech_dispatch",
      name: "Tech Dispatch",
      category: :lifestyle,
      description: "Daily and weekly technology news synthesis. Learns trends over time through accumulated lore.",
      suggested_team: "Tech Dispatch guild is purpose-built for this.",
      requires: [:any_members],
      source_definitions: [
        %{
          name: "Hacker News",
          source_type: "feed",
          config: %{"url" => "https://news.ycombinator.com/rss", "interval" => 1_800_000},
          book_id: "hacker_news_rss"
        },
        %{
          name: "The Verge",
          source_type: "feed",
          config: %{
            "url" => "https://www.theverge.com/rss/index.xml",
            "interval" => 1_800_000
          },
          book_id: "the_verge_rss"
        },
        %{
          name: "Ars Technica",
          source_type: "feed",
          config: %{
            "url" => "https://feeds.arstechnica.com/arstechnica/index",
            "interval" => 1_800_000
          },
          book_id: "ars_technica_rss"
        }
      ],
      step_definitions: [
        %{
          name: "Daily Tech Brief Step",
          description: "Synthesizes incoming tech articles into a clean daily briefing stored as lore.",
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
          description: "Synthesizes the week's lore into trend patterns.",
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
          context_providers: [%{"type" => "lore", "limit" => 30, "sort" => "newest"}]
        }
      ],
      quest_definition: %{
        name: "Tech Digest Loop Quest",
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
      name: "Sports Corner",
      category: :lifestyle,
      description: "Daily sports digest — scores, storylines, and what it all means. Builds a narrative arc over time.",
      suggested_team: "Sports Corner guild is purpose-built for this.",
      requires: [:any_members],
      source_definitions: [
        %{
          name: "ESPN",
          source_type: "feed",
          config: %{"url" => "https://www.espn.com/espn/rss/news", "interval" => 1_800_000},
          book_id: "espn_rss"
        },
        %{
          name: "BBC Sport",
          source_type: "feed",
          config: %{
            "url" => "http://feeds.bbci.co.uk/sport/rss.xml",
            "interval" => 1_800_000
          },
          book_id: "bbc_sport_rss"
        },
        %{
          name: "The Athletic",
          source_type: "feed",
          config: %{"url" => "https://theathletic.com/rss-feed/", "interval" => 1_800_000},
          book_id: "the_athletic_rss"
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
          description: "End-of-week narrative synthesis from the week's sports lore.",
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
          context_providers: [%{"type" => "lore", "limit" => 10, "sort" => "newest"}]
        }
      ],
      quest_definition: %{
        name: "Sports Digest Loop Quest",
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
      name: "Market Signals",
      category: :lifestyle,
      description:
        "Business and financial intelligence. Tracks market signals through daily synthesis and weekly pattern recognition.",
      suggested_team: "Market Signals guild is purpose-built for this.",
      requires: [:any_members],
      source_definitions: [
        %{
          name: "Reuters Business",
          source_type: "feed",
          config: %{
            "url" => "https://feeds.reuters.com/reuters/businessNews",
            "interval" => 1_800_000
          },
          book_id: "reuters_business_rss"
        },
        %{
          name: "Financial Times",
          source_type: "feed",
          config: %{"url" => "https://www.ft.com/rss/home", "interval" => 1_800_000},
          book_id: "ft_rss"
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
          context_providers: [%{"type" => "lore", "limit" => 10, "sort" => "newest"}],
          entry_title_template: "Market Roundup — {date}"
        }
      ],
      quest_definition: %{
        name: "Market Digest Loop Quest",
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
      name: "Culture Desk",
      category: :lifestyle,
      description: "Entertainment, music, film, culture. The tabloid voice meets the historian's memory.",
      suggested_team: "Culture Desk guild is purpose-built for this.",
      requires: [:any_members],
      source_definitions: [
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
        %{
          name: "Vulture",
          source_type: "feed",
          config: %{"url" => "https://www.vulture.com/rss/all.xml", "interval" => 3_600_000},
          book_id: "vulture_rss"
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
          output_type: "freeform"
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
          context_providers: [%{"type" => "lore", "limit" => 10, "sort" => "newest"}]
        }
      ],
      quest_definition: %{
        name: "Culture Digest Loop Quest",
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
      name: "Science Watch",
      category: :lifestyle,
      description:
        "Research and discovery synthesis. Translates science into plain language, separates signal from hype.",
      suggested_team: "Science Watch guild is purpose-built for this.",
      requires: [:any_members],
      source_definitions: [
        %{
          name: "Science Daily",
          source_type: "feed",
          config: %{
            "url" => "https://www.sciencedaily.com/rss/all.xml",
            "interval" => 3_600_000
          },
          book_id: "science_daily_rss"
        },
        %{
          name: "Nature News",
          source_type: "feed",
          config: %{"url" => "https://www.nature.com/nature.rss", "interval" => 3_600_000},
          book_id: "nature_news_rss"
        },
        %{
          name: "Ars Technica Science",
          source_type: "feed",
          config: %{
            "url" => "https://feeds.arstechnica.com/arstechnica/science",
            "interval" => 3_600_000
          },
          book_id: "ars_science_rss"
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
          context_providers: [%{"type" => "lore", "limit" => 20, "sort" => "newest"}]
        }
      ],
      quest_definition: %{
        name: "Science Digest Loop Quest",
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
