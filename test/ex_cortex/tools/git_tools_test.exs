defmodule ExCortex.Tools.GitToolsTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.GitCommit
  alias ExCortex.Tools.RunSandbox

  @tmp_dir Path.join(System.tmp_dir!(), "ex_cortex_git_test_#{:rand.uniform(99_999)}")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    System.cmd("git", ["init"], cd: @tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: @tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: @tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  test "git_commit stages files and commits" do
    File.write!(Path.join(@tmp_dir, "hello.ex"), "defmodule Hello, do: nil")

    assert {:ok, msg} =
             GitCommit.call(%{
               "files" => ["hello.ex"],
               "message" => "test commit",
               "working_dir" => @tmp_dir
             })

    assert msg =~ "Committed"
    {log, 0} = System.cmd("git", ["log", "--oneline"], cd: @tmp_dir)
    assert log =~ "test commit"
  end

  test "run_sandbox allows mix test" do
    assert RunSandbox.call(%{"command" => "mix test --help", "working_dir" => @tmp_dir}) !=
             {:error, "not allowed"}
  end

  test "run_sandbox blocks disallowed commands" do
    assert {:error, msg} =
             RunSandbox.call(%{"command" => "rm -rf /", "working_dir" => @tmp_dir})

    assert msg =~ "not allowed"
  end
end
