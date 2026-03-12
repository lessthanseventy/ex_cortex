defmodule ExCalibur.Sources.NextcloudWatcher do
  @moduledoc "Watches Nextcloud for file/note/calendar/talk activity via Activity API polling."

  @behaviour ExCalibur.Sources.Behaviour

  alias ExCalibur.Sources.SourceItem

  require Logger

  @impl true
  def init(config) do
    last_id = config["last_activity_id"] || 0
    {:ok, %{last_activity_id: last_id}}
  end

  @impl true
  def fetch(state, config) do
    url = config["url"] || ""
    username = config["username"] || ""
    password = config["password"] || ""

    if url == "" do
      {:error, "url is required"}
    else
      fetch_activities(state, config, url, username, password)
    end
  end

  @impl true
  def stop(_state), do: :ok

  defp fetch_activities(state, config, url, username, password) do
    activity_url = String.trim_trailing(url, "/") <> "/ocs/v2.php/apps/activity/api/v2/activity"

    headers = [
      {"OCS-APIRequest", "true"},
      {"Accept", "application/json"}
    ]

    params = %{"since" => state.last_activity_id, "limit" => 50}

    req_opts = maybe_add_auth([url: activity_url, headers: headers, params: params], username, password)

    case Req.get(req_opts) do
      {:ok, %{status: 200, body: %{"ocs" => %{"data" => activities}}}}
      when is_list(activities) and activities != [] ->
        items = Enum.map(activities, &activity_to_item(config, &1))

        max_id =
          activities
          |> Enum.map(& &1["activity_id"])
          |> Enum.max(fn -> state.last_activity_id end)

        Logger.info("[NextcloudWatcher] #{length(items)} new activities (up to id #{max_id})")
        {:ok, items, %{state | last_activity_id: max_id}}

      {:ok, %{status: 200}} ->
        {:ok, [], state}

      {:ok, %{status: 304}} ->
        {:ok, [], state}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_add_auth(opts, "", _), do: opts
  defp maybe_add_auth(opts, username, password), do: Keyword.put(opts, :auth, {:basic, "#{username}:#{password}"})

  defp activity_to_item(config, activity) do
    type = activity["type"] || "unknown"
    subject = activity["subject"] || ""
    object_name = activity["object_name"] || ""
    user = activity["user"] || ""

    content =
      "[Nextcloud #{type}] #{subject}" <>
        if(object_name == "", do: "", else: "\nFile: #{object_name}") <>
        if(user == "", do: "", else: "\nUser: #{user}")

    %SourceItem{
      source_id: config["source_id"],
      type: "nextcloud_activity",
      content: content,
      metadata: %{
        activity_type: type,
        subject: subject,
        object_type: activity["object_type"] || "",
        object_name: object_name,
        user: user,
        timestamp: activity["datetime"] || "",
        activity_id: activity["activity_id"]
      }
    }
  end
end
