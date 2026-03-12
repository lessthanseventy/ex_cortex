defmodule ExCalibur.Tools.NextcloudToolsTest do
  use ExUnit.Case, async: true

  describe "tool definitions" do
    test "search_nextcloud has valid tool definition" do
      tool = ExCalibur.Tools.SearchNextcloud.req_llm_tool()
      assert tool.name == "search_nextcloud"
    end

    test "read_nextcloud has valid tool definition" do
      tool = ExCalibur.Tools.ReadNextcloud.req_llm_tool()
      assert tool.name == "read_nextcloud"
    end

    test "read_nextcloud_notes has valid tool definition" do
      tool = ExCalibur.Tools.ReadNextcloudNotes.req_llm_tool()
      assert tool.name == "read_nextcloud_notes"
    end

    test "write_nextcloud has valid tool definition" do
      tool = ExCalibur.Tools.WriteNextcloud.req_llm_tool()
      assert tool.name == "write_nextcloud"
    end

    test "create_nextcloud_note has valid tool definition" do
      tool = ExCalibur.Tools.CreateNextcloudNote.req_llm_tool()
      assert tool.name == "create_nextcloud_note"
    end

    test "nextcloud_calendar has valid tool definition" do
      tool = ExCalibur.Tools.NextcloudCalendar.req_llm_tool()
      assert tool.name == "nextcloud_calendar"
    end

    test "nextcloud_talk has valid tool definition" do
      tool = ExCalibur.Tools.NextcloudTalk.req_llm_tool()
      assert tool.name == "nextcloud_talk"
    end
  end
end
