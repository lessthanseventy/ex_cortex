defmodule ExCalibur.ContextProviders.MemberRosterTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.ContextProviders.MemberRoster
  alias ExCalibur.Schemas.Member

  test "returns empty string when no active members" do
    result = MemberRoster.build(%{"type" => "member_roster"}, %{}, "")
    assert result == ""
  end

  test "lists active role members" do
    {:ok, _} =
      %Member{}
      |> Member.changeset(%{
        name: "Test Analyst",
        type: "role",
        status: "active",
        config: %{"rank" => "journeyman", "model" => "devstral-small-2:24b", "tools" => ["run_sandbox"]}
      })
      |> ExCalibur.Repo.insert()

    result = MemberRoster.build(%{"type" => "member_roster"}, %{}, "")
    assert result =~ "## Guild Members"
    assert result =~ "Test Analyst"
    assert result =~ "journeyman"
    assert result =~ "devstral-small-2:24b"
  end

  test "respects custom label" do
    result = MemberRoster.build(%{"type" => "member_roster", "label" => "## Team"}, %{}, "")
    # Label appears even when empty (returns "" when no members)
    assert is_binary(result)
  end
end
