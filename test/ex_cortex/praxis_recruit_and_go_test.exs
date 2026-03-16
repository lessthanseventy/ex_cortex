defmodule ExCortex.Praxis.RecruitAndGoTest do
  use ExCortex.DataCase

  alias ExCortex.Praxis

  describe "recruit_and_go/1" do
    test "installs rumination and steps" do
      template = Praxis.get("jira_ticket_triage")
      assert template

      {:ok, result} = Praxis.recruit_and_go(template)
      assert result.rumination
      assert result.steps_created != []
    end

    test "returns ok even for templates with no suggested_team" do
      template = Praxis.get("incident_postmortem")
      {:ok, result} = Praxis.recruit_and_go(template)
      assert result.neurons_recruited == []
    end
  end
end
