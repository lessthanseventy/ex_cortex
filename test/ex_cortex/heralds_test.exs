defmodule ExCortex.ExpressionsTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Expressions
  alias ExCortex.Expressions.Expression

  setup do
    ExCortex.Repo.delete_all(Expression)
    :ok
  end

  test "create and list expressions" do
    {:ok, _} =
      Expressions.create_expression(%{
        name: "slack:eng",
        type: "slack",
        config: %{"webhook_url" => "https://hooks.slack.com/x"}
      })

    assert length(Expressions.list_expressions()) == 1
  end

  test "get_by_name returns ok tuple" do
    {:ok, _} = Expressions.create_expression(%{name: "slack:eng", type: "slack", config: %{}})
    assert {:ok, %{name: "slack:eng"}} = Expressions.get_by_name("slack:eng")
  end

  test "get_by_name returns error when missing" do
    assert {:error, :not_found} = Expressions.get_by_name("nope")
  end

  test "list_by_type filters correctly" do
    {:ok, _} = Expressions.create_expression(%{name: "slack:eng", type: "slack", config: %{}})
    {:ok, _} = Expressions.create_expression(%{name: "wh:main", type: "webhook", config: %{}})
    assert length(Expressions.list_by_type("slack")) == 1
  end

  test "delete_expression removes it" do
    {:ok, h} = Expressions.create_expression(%{name: "slack:eng", type: "slack", config: %{}})
    Expressions.delete_expression(h)
    assert Expressions.list_expressions() == []
  end

  test "changeset rejects invalid type" do
    assert {:error, _} = Expressions.create_expression(%{name: "x", type: "carrier-pigeon", config: %{}})
  end
end
