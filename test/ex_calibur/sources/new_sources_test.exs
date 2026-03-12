defmodule ExCalibur.Sources.NewSourcesTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Sources.Book

  test "ObsidianWatcher module exists" do
    assert Code.ensure_loaded?(ExCalibur.Sources.ObsidianWatcher)
  end

  test "EmailSource module exists" do
    assert Code.ensure_loaded?(ExCalibur.Sources.EmailSource)
  end

  test "MediaSource module exists" do
    assert Code.ensure_loaded?(ExCalibur.Sources.MediaSource)
  end

  test "Book includes obsidian_watcher entry" do
    book = Book.get("obsidian_watcher")
    assert book.source_type == "obsidian"
  end

  test "Book includes email_inbox entry" do
    book = Book.get("email_inbox")
    assert book.source_type == "email"
  end

  test "Book includes youtube_channel entry" do
    book = Book.get("youtube_channel")
    assert book.source_type == "media"
  end
end
