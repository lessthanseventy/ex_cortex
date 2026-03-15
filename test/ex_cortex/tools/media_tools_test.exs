defmodule ExCortex.Tools.MediaToolsTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.DownloadMedia
  alias ExCortex.Tools.ExtractAudio
  alias ExCortex.Tools.ExtractFrames
  alias ExCortex.Tools.TranscribeAudio

  test "DownloadMedia returns a valid ReqLLM.Tool struct" do
    tool = DownloadMedia.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "download_media"
  end

  test "ExtractAudio returns a valid ReqLLM.Tool struct" do
    tool = ExtractAudio.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "extract_audio"
  end

  test "ExtractFrames returns a valid ReqLLM.Tool struct" do
    tool = ExtractFrames.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "extract_frames"
  end

  test "TranscribeAudio returns a valid ReqLLM.Tool struct" do
    tool = TranscribeAudio.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "transcribe_audio"
  end

  test "TranscribeAudio is in safe tier" do
    tools = ExCortex.Tools.Registry.resolve_tools(:all_safe)
    names = Enum.map(tools, & &1.name)
    assert "transcribe_audio" in names
    refute "download_media" in names
    refute "extract_audio" in names
    refute "extract_frames" in names
  end

  test "write-tier media tools appear in write but not safe" do
    safe_names = :all_safe |> ExCortex.Tools.Registry.resolve_tools() |> Enum.map(& &1.name)
    write_names = :write |> ExCortex.Tools.Registry.resolve_tools() |> Enum.map(& &1.name)

    assert "download_media" in write_names
    assert "extract_audio" in write_names
    assert "extract_frames" in write_names
    refute "download_media" in safe_names
    refute "extract_audio" in safe_names
    refute "extract_frames" in safe_names
  end

  test "TranscribeAudio stub returns error" do
    assert {:error, msg} = TranscribeAudio.call(%{"path" => "/tmp/test.wav"})
    assert String.contains?(msg, "Transcription not yet configured")
  end

  test "DownloadMedia has url as required parameter" do
    tool = DownloadMedia.req_llm_tool()
    assert "url" in tool.parameter_schema["required"]
  end

  test "ExtractAudio has input as required parameter" do
    tool = ExtractAudio.req_llm_tool()
    assert "input" in tool.parameter_schema["required"]
  end

  test "ExtractFrames has input as required parameter" do
    tool = ExtractFrames.req_llm_tool()
    assert "input" in tool.parameter_schema["required"]
  end
end
