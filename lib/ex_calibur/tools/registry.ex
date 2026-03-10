defmodule ExCalibur.Tools.Registry do
  @moduledoc """
  Registry of available tools, tiered by safety.

  Returns `ReqLLM.Tool` structs — pass them directly to
  `ReqLLM.generate_text(model, context, tools: tools)`.

  Usage:
    Registry.list_safe()              # safe tools only
    Registry.list_yolo()              # all tools
    Registry.get("query_lore")        # single tool by name
    Registry.resolve_tools(:all_safe) # from step/member config
  """

  @safe_entries [
    ExCalibur.Tools.QueryLore,
    ExCalibur.Tools.RunQuest
  ]

  @yolo_entries [
    ExCalibur.Tools.FetchUrl
  ]

  def list_safe, do: Enum.map(@safe_entries, & &1.req_llm_tool())

  def list_yolo, do: list_safe() ++ Enum.map(@yolo_entries, & &1.req_llm_tool())

  def get(name) when is_binary(name) do
    Enum.find(list_yolo(), &(&1.name == name))
  end

  @doc """
  Resolve a tools config value to a list of ReqLLM.Tool structs.

  Accepts:
  - :all_safe        — all safe tools
  - :yolo            — all tools (safe + yolo)
  - list of names    — specific tools by name
  - nil / []         — empty list
  """
  def resolve_tools(nil), do: []
  def resolve_tools([]), do: []
  def resolve_tools(:all_safe), do: list_safe()
  def resolve_tools(:yolo), do: list_yolo()

  def resolve_tools(names) when is_list(names) do
    Enum.flat_map(names, fn name ->
      case get(name) do
        nil -> []
        tool -> [tool]
      end
    end)
  end
end
