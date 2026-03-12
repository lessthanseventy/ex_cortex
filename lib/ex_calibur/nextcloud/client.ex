defmodule ExCalibur.Nextcloud.Client do
  @moduledoc false

  require Logger

  def base_url do
    ExCalibur.Settings.get(:nextcloud_url) ||
      System.get_env("NEXTCLOUD_URL", "http://localhost:8080")
  end

  def username do
    ExCalibur.Settings.get(:nextcloud_user) ||
      System.get_env("NEXTCLOUD_USER", "admin")
  end

  def password do
    ExCalibur.Settings.get(:nextcloud_password) ||
      System.get_env("NEXTCLOUD_PASSWORD", "admin")
  end

  def auth_headers do
    encoded = Base.encode64("#{username()}:#{password()}")
    [{"authorization", "Basic #{encoded}"}]
  end

  def webdav_url(path) do
    "#{base_url()}/remote.php/dav/files/#{username()}#{path}"
  end

  def ocs_url(path) do
    "#{base_url()}/ocs/v2.php#{path}"
  end

  # --- WebDAV Operations ---

  def propfind(path, depth \\ "1") do
    url = webdav_url(path)

    body = """
    <?xml version="1.0"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop>
        <d:getlastmodified/>
        <d:getcontentlength/>
        <d:resourcetype/>
        <d:displayname/>
      </d:prop>
    </d:propfind>
    """

    case Req.request(
           method: "PROPFIND",
           url: url,
           headers: auth_headers() ++ [{"depth", depth}, {"content-type", "application/xml"}],
           body: body
         ) do
      {:ok, %{status: status, body: resp_body}} when status in [200, 207] ->
        {:ok, parse_propfind(resp_body)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_file(path) do
    url = webdav_url(path)

    case Req.get(url, headers: auth_headers()) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def put_file(path, content) do
    url = webdav_url(path)

    case Req.put(url, headers: auth_headers(), body: content) do
      {:ok, %{status: status}} when status in [200, 201, 204] -> :ok
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def mkcol(path) do
    url = webdav_url(path)

    case Req.request(method: "MKCOL", url: url, headers: auth_headers()) do
      {:ok, %{status: status}} when status in [200, 201] -> :ok
      # already exists
      {:ok, %{status: 405}} -> :ok
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_resource(path) do
    url = webdav_url(path)

    case Req.delete(url, headers: auth_headers()) do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- OCS REST Operations ---

  def ocs_get(path) do
    url = ocs_url(path)

    case Req.get(url,
           headers: auth_headers() ++ [{"ocs-apirequest", "true"}, {"accept", "application/json"}]
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def ocs_post(path, body) do
    url = ocs_url(path)

    case Req.post(url,
           headers:
             auth_headers() ++
               [
                 {"ocs-apirequest", "true"},
                 {"accept", "application/json"},
                 {"content-type", "application/json"}
               ],
           json: body
         ) do
      {:ok, %{status: status, body: resp}} when status in [200, 201] -> {:ok, resp}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Notes API ---

  def list_notes do
    case Req.get("#{base_url()}/index.php/apps/notes/api/v1/notes",
           headers: auth_headers() ++ [{"accept", "application/json"}]
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_note(title, content, category \\ "") do
    case Req.post("#{base_url()}/index.php/apps/notes/api/v1/notes",
           headers:
             auth_headers() ++
               [{"content-type", "application/json"}, {"accept", "application/json"}],
           json: %{title: title, content: content, category: category}
         ) do
      {:ok, %{status: status, body: body}} when status in [200, 201] -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Talk API ---

  def talk_send(token, message) do
    ocs_post("/apps/spreed/api/v1/chat/#{token}", %{message: message})
  end

  def talk_rooms do
    ocs_get("/apps/spreed/api/v4/room")
  end

  # --- Activity API ---

  def activity(since \\ 0) do
    path = "/apps/activity/api/v2/activity?since=#{since}"
    ocs_get(path)
  end

  # --- Helpers ---

  defp parse_propfind(body) when is_binary(body) do
    ~r/<d:href>([^<]+)<\/d:href>/
    |> Regex.scan(body)
    |> Enum.map(fn [_, href] -> URI.decode(href) end)
  end

  defp parse_propfind(_), do: []

  def configured? do
    url = base_url()
    url != nil and url != ""
  end
end
