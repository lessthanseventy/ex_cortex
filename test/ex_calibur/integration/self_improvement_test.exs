defmodule ExCalibur.Integration.SelfImprovementTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Worktree

  @tmp_dir Path.join(System.tmp_dir!(), "self_improve_integration_#{:rand.uniform(99_999)}")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(Path.join(@tmp_dir, "lib"))
    System.cmd("git", ["init"], cd: @tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: @tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: @tmp_dir)
    File.write!(Path.join(@tmp_dir, "lib/hello.ex"), "defmodule Hello, do: nil")
    System.cmd("git", ["add", "."], cd: @tmp_dir)
    System.cmd("git", ["commit", "-m", "init"], cd: @tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    {:ok, repo: @tmp_dir}
  end

  test "worktree lifecycle: create, modify, commit, cleanup", %{repo: repo} do
    # Create worktree for issue 42
    {:ok, wt_path} = Worktree.create(repo, "42")
    assert File.exists?(wt_path)
    assert File.exists?(Path.join(wt_path, "lib/hello.ex"))

    # Simulate Code Writer modifying a file
    new_content = "defmodule Hello do\n  def greet, do: :hi\nend"
    File.write!(Path.join(wt_path, "lib/hello.ex"), new_content)
    {_, 0} = System.cmd("git", ["add", "lib/hello.ex"], cd: wt_path)
    {_, 0} = System.cmd("git", ["commit", "-m", "feat: add greet function"], cd: wt_path)

    # Verify commit exists on the self-improve branch
    {log, 0} = System.cmd("git", ["log", "--oneline", "self-improve/42"], cd: repo)
    assert log =~ "add greet function"

    # Verify the original repo's main branch is unaffected
    {main_content, 0} = System.cmd("git", ["show", "HEAD:lib/hello.ex"], cd: repo)
    assert main_content =~ "defmodule Hello, do: nil"

    # Cleanup
    :ok = Worktree.remove(repo, "42")
    refute File.exists?(wt_path)
  end

  test "multiple worktrees can coexist", %{repo: repo} do
    {:ok, path_a} = Worktree.create(repo, "issue-1")
    {:ok, path_b} = Worktree.create(repo, "issue-2")

    assert File.exists?(path_a)
    assert File.exists?(path_b)
    assert path_a != path_b

    Worktree.remove(repo, "issue-1")
    Worktree.remove(repo, "issue-2")
  end
end
