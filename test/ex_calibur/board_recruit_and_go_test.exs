defmodule ExCalibur.Board.RecruitAndGoTest do
  use ExCalibur.DataCase

  alias ExCalibur.Board

  describe "recruit_and_go/1" do
    test "installs quest and steps" do
      template = Board.get("jira_ticket_triage")
      assert template

      {:ok, result} = Board.recruit_and_go(template)
      assert result.quest
      assert result.steps_created != []
    end

    test "returns ok even for templates with no suggested_team" do
      template = Board.get("incident_postmortem")
      {:ok, result} = Board.recruit_and_go(template)
      assert result.members_recruited == []
    end
  end
end
