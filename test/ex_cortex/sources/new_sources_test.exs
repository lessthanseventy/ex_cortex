defmodule ExCortex.Senses.NewSourcesTest do
  use ExUnit.Case, async: true

  alias ExCortex.Senses.Reflex

  test "ObsidianWatcher module exists" do
    assert Code.ensure_loaded?(ExCortex.Senses.ObsidianWatcher)
  end

  test "EmailSource module exists" do
    assert Code.ensure_loaded?(ExCortex.Senses.EmailSense)
  end

  test "MediaSource module exists" do
    assert Code.ensure_loaded?(ExCortex.Senses.MediaSense)
  end

  test "Reflex includes obsidian_watcher entry" do
    reflex = Reflex.get("obsidian_watcher")
    assert reflex.source_type == "obsidian"
  end

  test "Reflex includes email_inbox entry" do
    reflex = Reflex.get("email_inbox")
    assert reflex.source_type == "email"
  end

  test "Reflex includes youtube_channel entry" do
    reflex = Reflex.get("youtube_channel")
    assert reflex.source_type == "media"
  end
end
