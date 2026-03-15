defmodule ExCortexWeb.Components.TUI do
  @moduledoc "TUI-styled components: panels, status indicators, key hints."
  use Phoenix.Component

  attr :title, :string, required: true
  attr :class, :string, default: ""
  attr :collapsed, :boolean, default: false
  attr :summary, :string, default: nil
  attr :on_toggle, :string, default: nil
  attr :toggle_value, :string, default: nil
  slot :inner_block, required: true

  def panel(%{on_toggle: toggle, collapsed: true} = assigns) when is_binary(toggle) do
    ~H"""
    <div class={"tui-panel #{@class}"}>
      <div
        class="tui-panel-header cursor-pointer select-none flex items-center justify-between"
        phx-click={@on_toggle}
        phx-value-panel={@toggle_value}
      >
        <span>┌─ {@title} ─</span>
        <span class="text-xs t-dim mr-1">▸</span>
      </div>
      <.panel_summary summary={@summary} />
    </div>
    """
  end

  def panel(%{on_toggle: toggle} = assigns) when is_binary(toggle) do
    ~H"""
    <div class={"tui-panel #{@class}"}>
      <div
        class="tui-panel-header cursor-pointer select-none flex items-center justify-between"
        phx-click={@on_toggle}
        phx-value-panel={@toggle_value}
      >
        <span>┌─ {@title} ─</span>
        <span class="text-xs t-dim mr-1">▾</span>
      </div>
      <div class="tui-panel-body">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

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

  attr :summary, :string, default: nil

  defp panel_summary(%{summary: nil} = assigns), do: ~H""

  defp panel_summary(assigns) do
    ~H"""
    <div class="tui-panel-body py-1">
      <p class="text-xs t-dim">{@summary}</p>
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
