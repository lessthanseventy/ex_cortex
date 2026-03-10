defmodule ExCalibur.Tools.RegistryTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Tools.Registry

  test "list_safe/0 returns ReqLLM.Tool structs for safe tools only" do
    tools = Registry.list_safe()
    assert Enum.all?(tools, &match?(%ReqLLM.Tool{}, &1))
    names = Enum.map(tools, & &1.name)
    assert "query_lore" in names
    assert "run_quest" in names
    refute "fetch_url" in names
  end

  test "list_yolo/0 returns all tools including unsafe" do
    tools = Registry.list_yolo()
    names = Enum.map(tools, & &1.name)
    assert "query_lore" in names
    assert "fetch_url" in names
  end

  test "get/1 returns a ReqLLM.Tool by name" do
    assert %ReqLLM.Tool{name: "query_lore"} = Registry.get("query_lore")
  end

  test "get/1 returns nil for unknown tool" do
    assert nil == Registry.get("does_not_exist")
  end

  test "resolve_tools/1 with :all_safe returns safe tools" do
    tools = Registry.resolve_tools(:all_safe)
    names = Enum.map(tools, & &1.name)
    assert "query_lore" in names
    refute "fetch_url" in names
  end

  test "resolve_tools/1 with :yolo returns all tools" do
    tools = Registry.resolve_tools(:yolo)
    names = Enum.map(tools, & &1.name)
    assert "fetch_url" in names
  end

  test "resolve_tools/1 with list of names returns matching tools" do
    tools = Registry.resolve_tools(["query_lore"])
    assert length(tools) == 1
    assert hd(tools).name == "query_lore"
  end
end
