defmodule ExCalibur.Charters.CreativeStudio do
  @moduledoc """
  Creative and content review guild charter.

  Uses builtin members: the-poet, the-historian,
  the-tabloid, brand-guardian.
  """

  alias ExCalibur.Members.BuiltinMember

  def metadata do
    members = [
      BuiltinMember.get("the-poet"),
      BuiltinMember.get("the-historian"),
      BuiltinMember.get("the-tabloid"),
      BuiltinMember.get("brand-guardian")
    ]

    %{
      name: "Creative Studio",
      description: "Creative and content review guild — evaluates brand voice, tone, and messaging, with flair.",
      roles: Enum.map(members, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    members = [
      {"the-poet", "The Poet"},
      {"the-historian", "The Historian"},
      {"the-tabloid", "The Tabloid"},
      {"brand-guardian", "Brand Guardian"}
    ]

    Enum.flat_map(members, fn {member_id, _name} ->
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
            "rank" => "journeyman",
            "model" => builtin.ranks.journeyman.model,
            "strategy" => builtin.ranks.journeyman.strategy
          }
        }
      ]
    end)
  end

  def quest_definitions do
    [
      %{
        name: "Brand Voice Check",
        description: "Brand voice consensus check by all members",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [
          %{
            "who" => "all",
            "preferred_who" => "brand-guardian",
            "when" => "on_trigger",
            "how" => "consensus"
          }
        ],
        source_ids: []
      },
      %{
        name: "Chronicle Entry",
        description: "Record events as a chronicle entry in the historian's voice",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [
          %{
            "who" => "master",
            "preferred_who" => "the-historian",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "freeform"
      },
      %{
        name: "Tone Review",
        description: "Quick tone review triggered by source content",
        status: "active",
        trigger: "source",
        schedule: nil,
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: []
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Content Review Campaign",
        description: "Manual content review — tone check then brand voice check on flag",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"quest_name" => "Tone Review", "flow" => "always"},
          %{"quest_name" => "Brand Voice Check", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    ]
  end
end
