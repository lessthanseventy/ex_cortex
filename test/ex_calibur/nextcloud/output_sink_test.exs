defmodule ExCalibur.Nextcloud.OutputSinkTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Nextcloud.OutputSink

  # Integration writes require a running Nextcloud server.
  # These tests verify the module compiles and exercises code paths
  # that don't require network access.

  describe "write_result/3" do
    test "returns error tuple when Nextcloud is unreachable" do
      # Default config has a URL so configured?() is true,
      # but the server isn't running so the write will fail.
      result = OutputSink.write_result("Test Quest", %{verdict: "pass"})
      assert {:error, _reason} = result
    end

    test "accepts binary result" do
      result = OutputSink.write_result("Binary Quest", "some plain text output")
      assert {:error, _reason} = result
    end

    test "accepts arbitrary term result" do
      result = OutputSink.write_result("Term Quest", {:ok, 42})
      assert {:error, _reason} = result
    end

    test "accepts folder option" do
      result = OutputSink.write_result("Custom Folder", %{verdict: "pass"}, folder: "/MyFolder")
      assert {:error, _reason} = result
    end
  end
end
