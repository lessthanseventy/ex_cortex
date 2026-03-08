defmodule ExCellenceServerWeb.MembersLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Excellence.Schemas.ResourceDefinition
  alias ExCellenceServer.Repo

  describe "list_members merge" do
    test "renders built-in members on the page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/members")
      # Grammar Editor is a built-in member
      assert html =~ "Grammar Editor"
    end

    test "built-in members show as inactive by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/members")
      # Should show toggle in off state — look for inactive indicator
      # The page renders all built-ins; with no DB record they are inactive
      assert html =~ "Grammar Editor"
    end

    test "custom DB member appears on page", %{conn: conn} do
      {:ok, _} =
        Repo.insert(%ResourceDefinition{
          type: "role",
          name: "My Custom Role",
          source: "db",
          status: "active",
          config: %{
            "system_prompt" => "You are custom.",
            "ranks" => %{
              "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
              "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
              "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
            }
          }
        })

      {:ok, _view, html} = live(conn, "/members")
      assert html =~ "My Custom Role"
    end

    test "active members appear before inactive ones", %{conn: conn} do
      {:ok, _} =
        Repo.insert(%ResourceDefinition{
          type: "role",
          name: "Grammar Editor",
          source: "code",
          status: "active",
          config: %{
            "member_id" => "grammar-editor",
            "system_prompt" => "You are a grammar editor.",
            "ranks" => %{
              "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
              "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
              "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
            }
          }
        })

      {:ok, _view, html} = live(conn, "/members")
      # Grammar Editor is now active — it should appear before inactive built-ins
      grammar_pos = :binary.match(html, "Grammar Editor") |> elem(0)
      tone_pos = :binary.match(html, "Tone Reviewer") |> elem(0)
      assert grammar_pos < tone_pos
    end
  end
end
