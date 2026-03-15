defmodule ExCortexWeb.Components.TUI do
  @moduledoc "TUI-styled components: panels, status indicators, key hints."
  use Phoenix.Component

  attr :title, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <div class={"tui-panel #{@class}"}>
      <div class="tui-panel-header">
        ┌─ {@title} ─
      </div>
      <div class="tui-panel-body">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :color, :string, default: "green"
  attr :label, :string, required: true

  def status(assigns) do
    color_class =
      case assigns.color do
        "green" -> "t-green"
        "amber" -> "t-amber"
        "red" -> "t-red"
        "cyan" -> "t-cyan"
        "pink" -> "t-pink"
        _ -> "t-dim"
      end

    assigns = assign(assigns, :color_class, color_class)

    ~H"""
    <span>
      <span class={@color_class}>●</span>
      <span class="ml-1">{@label}</span>
    </span>
    """
  end

  attr :hints, :list, required: true

  def key_hints(assigns) do
    ~H"""
    <div class="flex gap-4 text-xs t-muted">
      <span :for={{key, label} <- @hints}>
        <span class="tui-nav-key">[{key}]</span> {label}
      </span>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :key, :string, required: true
  attr :path, :string, required: true
  attr :active, :boolean, default: false

  def nav_link(assigns) do
    ~H"""
    <.link navigate={@path} class={"tui-nav-link #{if @active, do: "active"}"}>
      <span class="tui-nav-key">[{@key}]</span> {@label}
    </.link>
    """
  end
end
