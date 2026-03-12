defmodule ExCalibur.WorktreeTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Worktree

  @tmp_dir System.tmp_dir!() |> Path.join("ex_calibur_worktree_test_#{:rand.uniform(99999)}")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    System.cmd("git", ["init"], cd: @tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: @tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: @tmp_dir)
    File.write!(Path.join(@tmp_dir, "README.md"), "hello")
    System.cmd("git", ["add", "."], cd: @tmp_dir)
    System.cmd("git", ["commit", "-m", "init"], cd: @tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    {:ok, repo: @tmp_dir}
  end

  test "creates and removes a worktree", %{repo: repo} do
    {:ok, path} = Worktree.create(repo, "42")
    assert File.exists?(path)
    assert File.exists?(Path.join(path, "README.md"))

    :ok = Worktree.remove(repo, "42")
    refute File.exists?(path)
  end

  test "path/2 returns expected path without creating", %{repo: repo} do
    path = Worktree.path(repo, "99")
    refute File.exists?(path)
    assert path =~ ".worktrees/99"
  end
end
