defmodule ExCaliburWeb.MarkdownTest do
  use ExUnit.Case, async: true

  alias ExCaliburWeb.Markdown

  describe "render/1" do
    test "renders markdown to HTML" do
      result = Markdown.render("# Hello")
      assert result =~ "<h1>"
      assert result =~ "Hello"
    end

    test "renders code blocks" do
      result = Markdown.render("```elixir\nIO.puts(\"hi\")\n```")
      assert result =~ "IO"
    end

    test "handles nil gracefully" do
      assert Markdown.render(nil) == ""
    end

    test "handles empty string" do
      assert Markdown.render("") == ""
    end
  end
end
