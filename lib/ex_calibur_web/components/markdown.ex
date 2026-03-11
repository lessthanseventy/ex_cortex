defmodule ExCaliburWeb.Markdown do
  @moduledoc "MDEx-powered Markdown rendering helpers."

  def render(nil), do: ""
  def render(""), do: ""

  def render(markdown) when is_binary(markdown) do
    MDEx.to_html!(markdown,
      extension: [table: true, tasklist: true, strikethrough: true],
      render: [unsafe_: true]
    )
  end
end
