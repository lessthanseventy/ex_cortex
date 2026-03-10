defmodule ExCalibur.Charters.EverydayCouncil do
  @moduledoc """
  Everyday Council guild charter.

  Your personal life OS — advisory, journaling, news awareness, daily rhythms,
  priority management, and reflection. Uses builtin members: scope-realist,
  risk-assessor, the-optimist, challenger, evidence-collector, life-coach,
  journal-keeper, news-correspondent, the-historian.
  """

  alias ExCalibur.Members.BuiltinMember

  def metadata do
    members = [
      BuiltinMember.get("scope-realist"),
      BuiltinMember.get("risk-assessor"),
      BuiltinMember.get("the-optimist"),
      BuiltinMember.get("challenger"),
      BuiltinMember.get("evidence-collector"),
      BuiltinMember.get("life-coach"),
      BuiltinMember.get("journal-keeper"),
      BuiltinMember.get("news-correspondent"),
      BuiltinMember.get("the-historian")
    ]

    %{
      name: "Everyday Council",
      description:
        "Your personal life OS. Advisory, journaling, news, daily rhythms, priorities, and reflection — all in one place.",
      roles: Enum.map(members, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    members = [
      {"scope-realist", :journeyman},
      {"risk-assessor", :journeyman},
      {"the-optimist", :apprentice},
      {"challenger", :journeyman},
      {"evidence-collector", :apprentice},
      {"life-coach", :journeyman},
      {"journal-keeper", :apprentice},
      {"news-correspondent", :journeyman},
      {"the-historian", :journeyman}
    ]

    Enum.flat_map(members, fn {member_id, rank} ->
      builtin = BuiltinMember.get(member_id)

      [
        %{
          type: "role",
          name: builtin.name,
          status: "active",
          source: "db",
          config: %{
            "member_id" => member_id,
            "system_prompt" => builtin.system_prompt,
            "rank" => "apprentice",
            "model" => builtin.ranks.apprentice.model,
            "strategy" => builtin.ranks.apprentice.strategy
          }
        },
        %{
          type: "role",
          name: builtin.name,
          status: "active",
          source: "db",
          config: %{
            "member_id" => member_id,
            "system_prompt" => builtin.system_prompt,
            "rank" => to_string(rank),
            "model" => builtin.ranks[rank].model,
            "strategy" => builtin.ranks[rank].strategy
          }
        }
      ]
    end)
  end

  def quest_definitions do
    [
      # --- Advisory ---
      %{
        name: "Life Decision Review",
        description:
          "Submit a decision or dilemma for a full panel review. Each member weighs in from their perspective.",
        status: "active",
        trigger: "manual",
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        output_type: "verdict"
      },
      %{
        name: "Quick Take",
        description: "Fast advisory from a single grounded perspective. Good for gut checks.",
        status: "active",
        trigger: "manual",
        roster: [
          %{"who" => "journeyman", "preferred_who" => "life-coach", "when" => "on_trigger", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "verdict"
      },
      %{
        name: "Gut Check",
        description: "One-line sanity check. Drop an idea or plan and get a direct, honest take on whether it holds up.",
        status: "active",
        trigger: "manual",
        roster: [
          %{"who" => "journeyman", "preferred_who" => "challenger", "when" => "on_trigger", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "verdict"
      },
      %{
        name: "Risk Scan",
        description:
          "Focused risk assessment for a plan, decision, or idea. What could go wrong, how likely, what's the mitigation.",
        status: "active",
        trigger: "manual",
        roster: [
          %{"who" => "journeyman", "preferred_who" => "risk-assessor", "when" => "on_trigger", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "verdict"
      },
      %{
        name: "Priority Reset",
        description: "Drop your todo list or brain dump. Get a ranked, focused action plan that cuts through the noise.",
        status: "active",
        trigger: "manual",
        roster: [
          %{"who" => "journeyman", "preferred_who" => "scope-realist", "when" => "on_trigger", "how" => "solo"},
          %{"who" => "journeyman", "preferred_who" => "life-coach", "when" => "always", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "verdict"
      },
      %{
        name: "Event Debrief",
        description:
          "Something happened — big or small. Submit it for a full council debrief: what it means, what to do, what to watch.",
        status: "active",
        trigger: "manual",
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        output_type: "verdict"
      },
      %{
        name: "Optimism Check",
        description: "Feeling stuck, negative, or overwhelmed? Get a grounded reframe from the optimist perspective.",
        status: "active",
        trigger: "manual",
        roster: [
          %{"who" => "apprentice", "preferred_who" => "the-optimist", "when" => "on_trigger", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "verdict"
      },

      # --- Journaling & Intake ---
      %{
        name: "Journal Intake",
        description: "Drop a link, note, doc, or thought. The journal keeper processes it into a structured lore entry.",
        status: "active",
        trigger: "source",
        roster: [
          %{"who" => "apprentice", "preferred_who" => "journal-keeper", "when" => "on_trigger", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Journal — {date}"
      },
      %{
        name: "Daily Check-in",
        description: "Quick daily log — how you're feeling, what happened, what's on your mind. Keeps the journal alive.",
        status: "active",
        trigger: "manual",
        roster: [
          %{"who" => "apprentice", "preferred_who" => "journal-keeper", "when" => "on_trigger", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Check-in — {date}"
      },

      # --- Daily Rhythm ---
      %{
        name: "Morning Briefing",
        description:
          "Daily 8am briefing. Pulls from your recent journal entries and gives you a grounded start: priorities, context, and what to watch.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 8 * * *",
        roster: [
          %{"who" => "journeyman", "preferred_who" => "life-coach", "when" => "on_trigger", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Morning Briefing — {date}",
        context_providers: [%{"type" => "lore", "limit" => 10, "sort" => "newest"}]
      },
      %{
        name: "Midday Pulse",
        description:
          "Noon check-in. Quick scope-realist assessment of where you stand — what's done, what's slipping, what still matters today.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 12 * * *",
        roster: [
          %{"who" => "journeyman", "preferred_who" => "scope-realist", "when" => "on_trigger", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Midday Pulse — {date}",
        context_providers: [%{"type" => "lore", "limit" => 5, "sort" => "newest"}]
      },
      %{
        name: "Evening Wrap",
        description:
          "9pm daily wind-down. Synthesizes what happened today, what to carry forward, and what to let go. Sets up tomorrow's morning briefing.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 21 * * *",
        roster: [
          %{"who" => "journeyman", "preferred_who" => "journal-keeper", "when" => "on_trigger", "how" => "solo"},
          %{"who" => "journeyman", "preferred_who" => "the-optimist", "when" => "always", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Evening Wrap — {date}",
        context_providers: [%{"type" => "lore", "limit" => 8, "sort" => "newest"}]
      },

      # --- News & Briefings ---
      %{
        name: "News Briefing",
        description:
          "Drop a topic, question, or situation and get a news-correspondent take: what's happening, what's noise, what matters.",
        status: "active",
        trigger: "manual",
        roster: [
          %{"who" => "journeyman", "preferred_who" => "news-correspondent", "when" => "on_trigger", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "verdict"
      },
      %{
        name: "Weekly News Digest",
        description:
          "Friday digest of topics and developments relevant to what you've been tracking. Draws on your logged context.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 9 * * 5",
        roster: [
          %{"who" => "journeyman", "preferred_who" => "news-correspondent", "when" => "on_trigger", "how" => "solo"},
          %{"who" => "journeyman", "preferred_who" => "the-historian", "when" => "always", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Weekly News Digest — {date}",
        context_providers: [%{"type" => "lore", "limit" => 30, "sort" => "newest"}]
      },

      # --- Reflection & Synthesis ---
      %{
        name: "Weekly Reflection",
        description:
          "Weekly synthesis of accumulated journal entries into a reflection on patterns, progress, and themes.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 20 * * 0",
        roster: [
          %{"who" => "journeyman", "preferred_who" => "the-historian", "when" => "on_trigger", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Weekly Reflection — {date}",
        context_providers: [%{"type" => "lore", "limit" => 20}]
      },
      %{
        name: "Monthly Review",
        description:
          "Monthly deep synthesis — what happened, what changed, what's worth carrying forward. Draws on everything logged in the past month.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 10 1 * *",
        roster: [
          %{"who" => "journeyman", "preferred_who" => "the-historian", "when" => "on_trigger", "how" => "solo"},
          %{"who" => "journeyman", "preferred_who" => "evidence-collector", "when" => "always", "how" => "solo"}
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Monthly Review — {date}",
        context_providers: [%{"type" => "lore", "limit" => 60, "sort" => "newest"}]
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Intake Loop",
        description: "Continuous source intake — anything you drop gets processed and logged automatically.",
        status: "active",
        trigger: "source",
        steps: [
          %{"quest_name" => "Journal Intake", "flow" => "always"}
        ],
        source_ids: []
      },
      %{
        name: "Morning Start",
        description: "Daily 8am — check in with yourself, then get your morning briefing.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 8 * * *",
        steps: [
          %{"quest_name" => "Daily Check-in", "flow" => "always"},
          %{"quest_name" => "Morning Briefing", "flow" => "always"}
        ],
        source_ids: []
      },
      %{
        name: "Evening Close",
        description: "Daily 9pm — wrap the day, log it, set up tomorrow.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 21 * * *",
        steps: [
          %{"quest_name" => "Evening Wrap", "flow" => "always"}
        ],
        source_ids: []
      },
      %{
        name: "Weekly Close",
        description: "Friday evening — news digest then reflection, the full weekly loop.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 19 * * 5",
        steps: [
          %{"quest_name" => "Weekly News Digest", "flow" => "always"},
          %{"quest_name" => "Weekly Reflection", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
