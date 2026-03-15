defmodule ExCortex.Tools.RegistryTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.Registry

  test "resolve_tools(:all_safe) returns only safe tools" do
    tools = Registry.resolve_tools(:all_safe)
    assert Enum.all?(tools, &is_struct(&1, ReqLLM.Tool))
    names = Enum.map(tools, & &1.name)
    assert "query_memory" in names
    assert "query_axiom" in names
    refute "run_thought" in names
  end

  test "resolve_tools(:write) includes safe + write tools" do
    safe = Registry.resolve_tools(:all_safe)
    write = Registry.resolve_tools(:write)
    assert length(write) >= length(safe)
  end

  test "resolve_tools(:dangerous) includes all tiers" do
    write = Registry.resolve_tools(:write)
    dangerous = Registry.resolve_tools(:dangerous)
    assert length(dangerous) >= length(write)
    names = Enum.map(dangerous, & &1.name)
    assert "run_thought" in names
  end

  test "resolve_tools(:yolo) is alias for :dangerous" do
    assert Registry.resolve_tools(:yolo) == Registry.resolve_tools(:dangerous)
  end

  test "resolve_tools(nil) returns empty list" do
    assert Registry.resolve_tools(nil) == []
  end

  test "resolve_tools(names_list) returns only the named tools" do
    tools = Registry.resolve_tools(["query_memory", "query_axiom"])
    names = Enum.map(tools, & &1.name)
    assert length(tools) == 2
    assert "query_memory" in names
    assert "query_axiom" in names
  end

  test "Registry.get/1 returns a ReqLLM.Tool struct for a known tool" do
    tool = Registry.get("query_memory")
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "query_memory"
  end

  test "Registry.get/1 returns nil for unknown tool" do
    assert Registry.get("does_not_exist") == nil
  end
end
