defmodule ExCortex.Nextcloud.OutputSinkTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Nextcloud.OutputSink

  # Smoke tests — verify code paths don't crash.
  # Result depends on whether a Nextcloud instance is reachable.

  describe "write_result/3" do
    test "returns ok or error tuple" do
      result = OutputSink.write_result("Test Rumination", %{verdict: "pass"})
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts binary result" do
      result = OutputSink.write_result("Binary Rumination", "some plain text output")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts arbitrary term result" do
      result = OutputSink.write_result("Term Rumination", {:ok, 42})
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts folder option" do
      result = OutputSink.write_result("Custom Folder", %{verdict: "pass"}, folder: "/MyFolder")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
