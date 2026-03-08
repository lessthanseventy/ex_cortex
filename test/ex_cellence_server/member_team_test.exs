defmodule ExCellenceServer.MemberTeamTest do
  use ExCellenceServer.DataCase, async: true

  alias Excellence.Schemas.Member

  test "team can be set on a member changeset" do
    attrs = %{
      type: "role",
      name: "test-member",
      source: "db",
      status: "active",
      team: "alpha"
    }

    changeset = Member.changeset(%Member{}, attrs)
    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :team) == "alpha"
  end

  test "team defaults to nil when not provided" do
    attrs = %{type: "role", name: "test-member", source: "db"}
    changeset = Member.changeset(%Member{}, attrs)
    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :team) == nil
  end

  test "team is persisted to the database" do
    attrs = %{
      type: "role",
      name: "team-member",
      source: "db",
      status: "active",
      team: "bravo"
    }

    {:ok, member} =
      %Member{}
      |> Member.changeset(attrs)
      |> ExCellenceServer.Repo.insert()

    assert member.team == "bravo"

    fetched = ExCellenceServer.Repo.get!(Member, member.id)
    assert fetched.team == "bravo"
  end
end
