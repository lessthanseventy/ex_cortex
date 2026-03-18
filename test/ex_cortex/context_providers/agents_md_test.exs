defmodule ExCortex.ContextProviders.AgentsMdTest do
  use ExUnit.Case, async: true

  alias ExCortex.ContextProviders.AgentsMd

  setup do
    dir = Path.join(System.tmp_dir!(), "agents_md_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "returns content wrapped in tags when file exists", %{dir: dir} do
    File.write!(Path.join(dir, "AGENTS.md"), "# Rules\nAlways test first.")
    result = AgentsMd.build(%{"type" => "agents_md", "repo_path" => dir}, %{}, "input")
    assert String.contains?(result, "<agents_md")
    assert String.contains?(result, "Always test first.")
    assert String.contains?(result, "</agents_md>")
  end

  test "returns empty string when file doesn't exist", %{dir: dir} do
    assert "" == AgentsMd.build(%{"type" => "agents_md", "repo_path" => dir}, %{}, "input")
  end

  test "supports custom filename", %{dir: dir} do
    File.write!(Path.join(dir, "CLAUDE.md"), "# Claude Rules")

    result =
      AgentsMd.build(%{"type" => "agents_md", "repo_path" => dir, "filename" => "CLAUDE.md"}, %{}, "input")

    assert String.contains?(result, "Claude Rules")
  end

  test "returns empty for empty file", %{dir: dir} do
    File.write!(Path.join(dir, "AGENTS.md"), "")
    assert "" == AgentsMd.build(%{"type" => "agents_md", "repo_path" => dir}, %{}, "input")
  end

  test "returns empty when no repo_path" do
    assert "" == AgentsMd.build(%{"type" => "agents_md"}, %{}, "input")
  end
end
