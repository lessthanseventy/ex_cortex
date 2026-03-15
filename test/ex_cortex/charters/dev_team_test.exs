defmodule ExCortex.Pathways.DevTeamTest do
  use ExUnit.Case, async: true

  alias ExCortex.Pathways.DevTeam

  test "metadata returns expected neuron names" do
    meta = DevTeam.metadata()
    names = Enum.map(meta.roles, & &1.name)
    assert "Project Manager" in names
    assert "Product Analyst" in names
    assert "Code Writer" in names
    assert "Code Reviewer" in names
    assert "QA / Test Writer" in names
    assert "UX Designer" in names
    assert "Code Auditor" in names
    assert "Backlog Manager" in names
    assert length(names) == 8
  end
end
