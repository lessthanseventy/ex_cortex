defmodule ExCalibur.Sources.GithubIssueWatcherTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Sources.GithubIssueWatcher

  test "init with valid config returns ok with empty seen_ids" do
    assert {:ok, %{seen_ids: []}} =
             GithubIssueWatcher.init(%{"repo" => "owner/repo", "label" => "self-improvement"})
  end

  test "init errors without repo" do
    assert {:error, _} = GithubIssueWatcher.init(%{})
  end

  test "init errors with empty repo" do
    assert {:error, _} = GithubIssueWatcher.init(%{"repo" => ""})
  end
end
