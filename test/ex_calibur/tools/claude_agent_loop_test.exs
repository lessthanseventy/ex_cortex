defmodule ExCalibur.ClaudeAgentLoopTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.ClaudeClient

  test "complete_with_tools/4 returns {:error, _} or {:ok, _} — does not crash without API key" do
    result = ClaudeClient.complete_with_tools("claude_haiku", "You are helpful", "Say hi", [])
    assert match?({:error, _}, result) or match?({:ok, _}, result)
  end

  test "complete_with_tools/4 returns {:error, _} for unknown tier" do
    result = ClaudeClient.complete_with_tools("claude_blorp", "sys", "msg", [])
    assert {:error, _} = result
  end
end
