defmodule ExCalibur.Tools.WebToolsTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Tools.{WebFetch, WebSearch}

  test "WebFetch returns a valid ReqLLM.Tool struct" do
    tool = WebFetch.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "web_fetch"
  end

  test "WebSearch returns a valid ReqLLM.Tool struct" do
    tool = WebSearch.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "web_search"
  end

  test "WebFetch has url as required parameter" do
    tool = WebFetch.req_llm_tool()
    assert "url" in tool.parameter_schema["required"]
  end

  test "WebSearch has query as required parameter" do
    tool = WebSearch.req_llm_tool()
    assert "query" in tool.parameter_schema["required"]
  end

  test "web tools appear in safe tier" do
    tools = ExCalibur.Tools.Registry.resolve_tools(:all_safe)
    names = Enum.map(tools, & &1.name)
    assert "web_fetch" in names
    assert "web_search" in names
  end

  test "FetchUrl is still present in safe tier" do
    tools = ExCalibur.Tools.Registry.resolve_tools(:all_safe)
    names = Enum.map(tools, & &1.name)
    assert "fetch_url" in names
  end
end
