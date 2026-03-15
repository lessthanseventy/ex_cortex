defmodule ExCortex.Tools.FileToolsTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.EditFile
  alias ExCortex.Tools.ListFiles
  alias ExCortex.Tools.ReadFile
  alias ExCortex.Tools.WriteFile

  @tmp_dir Path.join(System.tmp_dir!(), "ex_cortex_tool_test")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  describe "ReadFile" do
    test "reads existing file" do
      path = Path.join(@tmp_dir, "hello.txt")
      File.write!(path, "hello world")
      assert {:ok, "hello world"} = ReadFile.call(%{"path" => "hello.txt", "working_dir" => @tmp_dir})
    end

    test "rejects path traversal" do
      assert {:error, msg} = ReadFile.call(%{"path" => "../../../etc/passwd", "working_dir" => @tmp_dir})
      assert msg =~ "outside"
    end
  end

  describe "WriteFile" do
    test "writes new file" do
      path = Path.join(@tmp_dir, "new.txt")
      assert {:ok, _} = WriteFile.call(%{"path" => "new.txt", "content" => "hi", "working_dir" => @tmp_dir})
      assert File.read!(path) == "hi"
    end

    test "rejects path traversal" do
      assert {:error, _} = WriteFile.call(%{"path" => "../../escape.txt", "content" => "x", "working_dir" => @tmp_dir})
    end
  end

  describe "EditFile" do
    test "replaces text in file" do
      path = Path.join(@tmp_dir, "edit.txt")
      File.write!(path, "hello world")

      assert {:ok, _} =
               EditFile.call(%{"path" => "edit.txt", "old" => "world", "new" => "elixir", "working_dir" => @tmp_dir})

      assert File.read!(path) == "hello elixir"
    end

    test "errors when old text not found" do
      path = Path.join(@tmp_dir, "edit.txt")
      File.write!(path, "hello")

      assert {:error, _} =
               EditFile.call(%{"path" => "edit.txt", "old" => "missing", "new" => "x", "working_dir" => @tmp_dir})
    end
  end

  describe "ListFiles" do
    test "lists files matching pattern" do
      File.write!(Path.join(@tmp_dir, "a.ex"), "")
      File.write!(Path.join(@tmp_dir, "b.ex"), "")
      File.write!(Path.join(@tmp_dir, "c.txt"), "")
      assert {:ok, result} = ListFiles.call(%{"pattern" => "*.ex", "working_dir" => @tmp_dir})
      assert result =~ "a.ex"
      assert result =~ "b.ex"
      refute result =~ "c.txt"
    end
  end
end
