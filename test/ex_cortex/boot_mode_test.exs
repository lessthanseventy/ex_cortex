defmodule ExCortex.BootModeTest do
  use ExUnit.Case, async: true

  alias ExCortex.BootMode

  test "parses empty args as :full" do
    assert BootMode.parse([]) == :full
  end

  test "parses 'server' as :server" do
    assert BootMode.parse(["server"]) == :server
  end

  test "parses 'tui' as :tui" do
    assert BootMode.parse(["tui"]) == :tui
  end

  test "parses 'hud' as :hud" do
    assert BootMode.parse(["hud"]) == :hud
  end

  test "unknown args default to :full" do
    assert BootMode.parse(["banana"]) == :full
  end
end
