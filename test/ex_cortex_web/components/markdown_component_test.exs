defmodule ExCortexWeb.MarkdownComponentTest do
  use ExCortexWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  describe "md/1 component" do
    test "renders markdown content" do
      assigns = %{content: "**bold text**"}

      html =
        rendered_to_string(~H"""
        <ExCortexWeb.CoreComponents.md content={@content} />
        """)

      assert html =~ "<strong>"
      assert html =~ "bold text"
    end

    test "renders nil as empty" do
      assigns = %{content: nil}

      html =
        rendered_to_string(~H"""
        <ExCortexWeb.CoreComponents.md content={@content} />
        """)

      refute html =~ "<p>"
    end
  end
end
