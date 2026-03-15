defmodule ExCortex.Tools.VisionToolsTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.AnalyzeVideo
  alias ExCortex.Tools.DescribeImage
  alias ExCortex.Tools.ReadImageText

  test "DescribeImage returns a valid ReqLLM.Tool struct" do
    tool = DescribeImage.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "describe_image"
  end

  test "ReadImageText returns a valid ReqLLM.Tool struct" do
    tool = ReadImageText.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "read_image_text"
  end

  test "AnalyzeVideo returns a valid ReqLLM.Tool struct" do
    tool = AnalyzeVideo.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "analyze_video"
  end

  test "DescribeImage has path as required parameter" do
    tool = DescribeImage.req_llm_tool()
    assert "path" in tool.parameter_schema["required"]
  end

  test "ReadImageText has path as required parameter" do
    tool = ReadImageText.req_llm_tool()
    assert "path" in tool.parameter_schema["required"]
  end

  test "AnalyzeVideo has path as required parameter" do
    tool = AnalyzeVideo.req_llm_tool()
    assert "path" in tool.parameter_schema["required"]
  end

  test "vision tools are in safe tier" do
    tools = ExCortex.Tools.Registry.resolve_tools(:all_safe)
    names = Enum.map(tools, & &1.name)
    assert "describe_image" in names
    assert "read_image_text" in names
    assert "analyze_video" in names
  end

  test "DescribeImage returns error for missing file" do
    assert {:error, msg} = DescribeImage.call(%{"path" => "/tmp/nonexistent_image_xyz.jpg"})
    assert String.contains?(msg, "File not found")
  end

  test "ReadImageText returns error for missing file" do
    assert {:error, msg} = ReadImageText.call(%{"path" => "/tmp/nonexistent_image_xyz.jpg"})
    assert String.contains?(msg, "File not found")
  end

  test "AnalyzeVideo returns error for missing file" do
    assert {:error, msg} = AnalyzeVideo.call(%{"path" => "/tmp/nonexistent_video_xyz.mp4"})
    assert String.contains?(msg, "File not found")
  end
end
