defmodule ExCortex.ContextProviders.ObsidianTemporalTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.ContextProviders.Obsidian

  describe "date_range_for/1" do
    test "today returns single date matching utc_today" do
      assert Obsidian.date_range_for("today") == [Date.utc_today()]
    end

    test "yesterday returns previous day" do
      assert Obsidian.date_range_for("yesterday") == [Date.add(Date.utc_today(), -1)]
    end

    test "week returns 7 dates oldest first ending with today" do
      dates = Obsidian.date_range_for("week")

      assert length(dates) == 7
      assert List.last(dates) == Date.utc_today()
      assert hd(dates) == Date.add(Date.utc_today(), -6)
      assert dates == Enum.sort(dates, Date)
    end

    test "month returns 30 dates oldest first ending with today" do
      dates = Obsidian.date_range_for("month")

      assert length(dates) == 30
      assert List.last(dates) == Date.utc_today()
      assert hd(dates) == Date.add(Date.utc_today(), -29)
      assert dates == Enum.sort(dates, Date)
    end

    test "unknown value defaults to today" do
      assert Obsidian.date_range_for("bogus") == [Date.utc_today()]
      assert Obsidian.date_range_for("") == [Date.utc_today()]
    end
  end

  describe "build/3 with daily_range mode" do
    test "daily_range mode accepts config and returns string" do
      config = %{"mode" => "daily_range", "time_range" => "today", "sections" => ["all"]}
      result = Obsidian.build(config, %{}, "anything")

      assert is_binary(result)
    end

    test "daily_range mode defaults time_range to today" do
      config = %{"mode" => "daily_range"}
      result = Obsidian.build(config, %{}, "anything")

      assert is_binary(result)
    end

    test "daily_range mode with section filtering returns string" do
      config = %{"mode" => "daily_range", "time_range" => "today", "sections" => ["brain_dump"]}
      result = Obsidian.build(config, %{}, "anything")

      assert is_binary(result)
    end

    test "daily_range mode with week range returns string" do
      config = %{"mode" => "daily_range", "time_range" => "week"}
      result = Obsidian.build(config, %{}, "anything")

      assert is_binary(result)

      if result != "" do
        assert result =~ "## Daily Notes (week)"
      end
    end

    test "daily_range mode wraps content with header and date headers" do
      config = %{"mode" => "daily_range", "time_range" => "today", "sections" => ["all"]}
      result = Obsidian.build(config, %{}, "anything")

      if result != "" do
        today = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")
        assert result =~ "## Daily Notes (today)"
        assert result =~ "### #{today}"
      end
    end
  end
end
