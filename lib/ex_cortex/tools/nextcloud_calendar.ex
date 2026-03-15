defmodule ExCortex.Tools.NextcloudCalendar do
  @moduledoc false

  alias ExCortex.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "nextcloud_calendar",
      description: "Create a calendar event in Nextcloud.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "title" => %{"type" => "string", "description" => "Event title"},
          "start" => %{
            "type" => "string",
            "description" => "Start datetime ISO 8601, e.g. '2026-03-15T10:00:00'"
          },
          "end" => %{"type" => "string", "description" => "End datetime ISO 8601"},
          "description" => %{"type" => "string", "description" => "Optional event description"}
        },
        "required" => ["title", "start", "end"]
      },
      callback: &call/1
    )
  end

  def call(%{"title" => title, "start" => start_dt, "end" => end_dt} = params) do
    desc = params["description"] || ""
    uid = "excalibur-#{System.unique_integer([:positive])}"

    vevent = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//ExCortex//EN
    BEGIN:VEVENT
    UID:#{uid}
    DTSTART:#{format_ical_dt(start_dt)}
    DTEND:#{format_ical_dt(end_dt)}
    SUMMARY:#{title}
    DESCRIPTION:#{desc}
    END:VEVENT
    END:VCALENDAR
    """

    cal_path = "/remote.php/dav/calendars/#{Client.username()}/personal/#{uid}.ics"
    url = "#{Client.base_url()}#{cal_path}"

    case Req.put(url,
           headers: Client.auth_headers() ++ [{"content-type", "text/calendar"}],
           body: vevent
         ) do
      {:ok, %{status: status}} when status in [200, 201, 204] ->
        {:ok, "Created calendar event '#{title}' (#{start_dt} - #{end_dt})"}

      {:ok, %{status: status}} ->
        {:error, "Calendar create failed with status #{status}"}

      {:error, reason} ->
        {:error, "Calendar create failed: #{inspect(reason)}"}
    end
  end

  defp format_ical_dt(iso_string) do
    String.replace(iso_string, ~r/[-:]/, "")
  end
end
