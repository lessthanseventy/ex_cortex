defmodule ExCortex.ClaudeAgentLoopTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.ClaudeClient

  test "complete_with_tools/4 returns 3-tuple — does not crash without API key" do
    result = ClaudeClient.complete_with_tools("claude_haiku", "You are helpful", "Say hi", [])
    assert match?({:error, _, _}, result) or match?({:ok, _, _}, result)
  end

  test "complete_with_tools/4 returns {:error, _} for unknown tier" do
    result = ClaudeClient.complete_with_tools("claude_blorp", "sys", "msg", [])
    assert {:error, _} = result
  end
end
