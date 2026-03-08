defmodule ExCellenceServer.SandboxTest do
  use ExUnit.Case, async: true

  alias ExCellenceServer.Sandbox

  describe "run/2 host mode" do
    test "runs a command and captures output" do
      config = %{cmd: "echo hello"}
      {:ok, output, 0} = Sandbox.run(config, "/tmp")
      assert output =~ "hello"
    end

    test "returns non-zero exit code on failure" do
      config = %{cmd: "false"}
      {:ok, _output, exit_code} = Sandbox.run(config, "/tmp")
      assert exit_code != 0
    end

    test "returns error on timeout" do
      config = %{cmd: "sleep 10", timeout: 100}
      assert {:error, :timeout} = Sandbox.run(config, "/tmp")
    end
  end

  describe "wrap_content/3" do
    test "wraps source content and tool output" do
      result = Sandbox.wrap_content("source stuff", "tool output", "mix test")
      assert result =~ "## Source Content"
      assert result =~ "source stuff"
      assert result =~ "## Tool Output (mix test)"
      assert result =~ "tool output"
    end
  end
end
