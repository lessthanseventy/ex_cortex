defmodule ExCalibur.Tools.RegistryTest do
  use ExUnit.Case, async: true
  alias ExCalibur.Tools.Registry

  test "resolve_tools(:all_safe) returns only safe tools" do
    tools = Registry.resolve_tools(:all_safe)
    assert Enum.all?(tools, &is_struct(&1, ReqLLM.Tool))
    names = Enum.map(tools, & &1.name)
    assert "query_lore" in names
    refute "run_quest" in names
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
    assert "run_quest" in names
  end

  test "resolve_tools(:yolo) is alias for :dangerous" do
    assert Registry.resolve_tools(:yolo) == Registry.resolve_tools(:dangerous)
  end
end
