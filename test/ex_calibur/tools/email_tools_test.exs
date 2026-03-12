defmodule ExCalibur.Tools.EmailToolsTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Tools.ReadEmail
  alias ExCalibur.Tools.SearchEmail
  alias ExCalibur.Tools.SendEmail

  test "SearchEmail returns a valid ReqLLM.Tool struct" do
    tool = SearchEmail.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "search_email"
  end

  test "ReadEmail returns a valid ReqLLM.Tool struct" do
    tool = ReadEmail.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "read_email"
  end

  test "SendEmail returns a valid ReqLLM.Tool struct" do
    tool = SendEmail.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "send_email"
  end

  test "Registry includes email read tools in all_safe" do
    tools = ExCalibur.Tools.Registry.resolve_tools(:all_safe)
    names = Enum.map(tools, & &1.name)
    assert "search_email" in names
    assert "read_email" in names
    refute "send_email" in names
  end

  test "Registry includes SendEmail in dangerous tier" do
    tools = ExCalibur.Tools.Registry.resolve_tools(:dangerous)
    names = Enum.map(tools, & &1.name)
    assert "send_email" in names
    # safe tools also present
    assert "search_email" in names
    assert "read_email" in names
  end

  test "SendEmail is not in write tier" do
    tools = ExCalibur.Tools.Registry.resolve_tools(:write)
    names = Enum.map(tools, & &1.name)
    refute "send_email" in names
  end
end
