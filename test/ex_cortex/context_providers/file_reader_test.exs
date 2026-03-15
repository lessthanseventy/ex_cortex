defmodule ExCortex.ContextProviders.FileReaderTest do
  use ExUnit.Case, async: true

  alias ExCortex.ContextProviders.FileReader

  @tag :tmp_dir
  test "returns empty string when files list is empty" do
    result = FileReader.build(%{"type" => "file_reader", "files" => []}, %{}, "")
    assert result == ""
  end

  test "returns empty string when file does not exist" do
    result = FileReader.build(%{"type" => "file_reader", "files" => ["nonexistent/path.ex"]}, %{}, "")
    assert result == ""
  end

  test "injects file content as markdown code block" do
    result = FileReader.build(%{"type" => "file_reader", "files" => ["mix.exs"]}, %{}, "")
    assert result =~ "### mix.exs"
    assert result =~ "```elixir"
    assert result =~ "ExCortex.MixProject"
  end

  test "respects custom label" do
    result = FileReader.build(%{"type" => "file_reader", "files" => ["mix.exs"], "label" => "## My Files"}, %{}, "")
    assert result =~ "## My Files"
  end

  test "truncates large files and appends truncation marker" do
    result = FileReader.build(%{"type" => "file_reader", "files" => ["mix.exs"], "max_bytes_per_file" => 10}, %{}, "")
    assert result =~ "... (truncated)"
  end

  test "does not append truncation marker for small files" do
    result =
      FileReader.build(%{"type" => "file_reader", "files" => ["mix.exs"], "max_bytes_per_file" => 100_000}, %{}, "")

    refute result =~ "... (truncated)"
  end
end
