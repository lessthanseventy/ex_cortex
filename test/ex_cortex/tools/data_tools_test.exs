defmodule ExCortex.Tools.DataToolsTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.ConvertDocument
  alias ExCortex.Tools.JqQuery
  alias ExCortex.Tools.ReadPdf

  test "JqQuery returns a valid ReqLLM.Tool struct" do
    tool = JqQuery.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "jq_query"
  end

  test "ReadPdf returns a valid ReqLLM.Tool struct" do
    tool = ReadPdf.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "read_pdf"
  end

  test "ConvertDocument returns a valid ReqLLM.Tool struct" do
    tool = ConvertDocument.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "convert_document"
  end

  test "all data tools appear in safe tier" do
    tools = ExCortex.Tools.Registry.resolve_tools(:all_safe)
    names = Enum.map(tools, & &1.name)
    assert "jq_query" in names
    assert "read_pdf" in names
    assert "convert_document" in names
  end

  test "JqQuery has correct required parameters" do
    tool = JqQuery.req_llm_tool()
    required = tool.parameter_schema["required"]
    assert "expression" in required
    assert "json" in required
  end

  test "ReadPdf has correct required parameters" do
    tool = ReadPdf.req_llm_tool()
    required = tool.parameter_schema["required"]
    assert "path" in required
  end

  test "ConvertDocument has correct required parameters" do
    tool = ConvertDocument.req_llm_tool()
    required = tool.parameter_schema["required"]
    assert "path" in required
    assert "from" in required
    assert "to" in required
  end
end
