# Nextcloud Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add Nextcloud to ExCalibur's docker stack and integrate it as a source, tool provider, and output sink for agent guilds.

**Architecture:** Nextcloud + MariaDB added to docker-compose. New `ExCalibur.Nextcloud.Client` module wraps Req for WebDAV/OCS API calls with basic auth. Event-driven source uses Nextcloud Flow webhooks for file events + Activity API polling for Talk/Calendar/Notes. Seven new tools across three tiers. Output sink writes quest results to Nextcloud via WebDAV.

**Tech Stack:** Nextcloud (docker), MariaDB, Req (HTTP), WebDAV (PROPFIND/GET/PUT/MKCOL), OCS REST API, CalDAV

---

### Task 0: Docker Infrastructure

**Files:**
- Modify: `docker-compose.yml`
- Create: `docker/init-nextcloud.sh`

**Step 1: Add nextcloud-db service to docker-compose.yml**

Add after the `grafana` service, before `app`:

```yaml
  nextcloud-db:
    image: docker.io/mariadb:11
    environment:
      MYSQL_ROOT_PASSWORD: nextcloud
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: nextcloud
    volumes:
      - nextcloud_db:/var/lib/mysql
    healthcheck:
      test: ["CMD-SHELL", "mariadb-admin ping -h localhost -u root -pnextcloud"]
      interval: 5s
      timeout: 5s
      retries: 5
```

**Step 2: Add nextcloud service to docker-compose.yml**

Add after `nextcloud-db`:

```yaml
  nextcloud:
    image: docker.io/nextcloud:latest
    depends_on:
      nextcloud-db:
        condition: service_healthy
    ports:
      - "8080:80"
    environment:
      MYSQL_HOST: nextcloud-db
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: nextcloud
      NEXTCLOUD_ADMIN_USER: admin
      NEXTCLOUD_ADMIN_PASSWORD: admin
      NEXTCLOUD_TRUSTED_DOMAINS: "localhost nextcloud"
    volumes:
      - nextcloud_data:/var/www/html
      - ./docker/init-nextcloud.sh:/init-nextcloud.sh
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost/status.php || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 30
      start_period: 60s
```

**Step 3: Add volumes**

Add to the `volumes:` section at the bottom:

```yaml
  nextcloud_data:
  nextcloud_db:
```

**Step 4: Add NEXTCLOUD_URL to app service environment**

```yaml
      NEXTCLOUD_URL: ${NEXTCLOUD_URL:-http://nextcloud:80}
      NEXTCLOUD_USER: ${NEXTCLOUD_USER:-admin}
      NEXTCLOUD_PASSWORD: ${NEXTCLOUD_PASSWORD:-admin}
```

**Step 5: Create docker/init-nextcloud.sh**

```bash
#!/bin/bash
# Wait for Nextcloud to finish initial setup
until curl -s http://localhost/status.php | grep -q '"installed":true'; do
  echo "Waiting for Nextcloud installation..."
  sleep 5
done

echo "Nextcloud installed, configuring apps..."

# Enable apps via occ
su -s /bin/bash www-data -c "php occ app:enable notes"
su -s /bin/bash www-data -c "php occ app:enable calendar"
su -s /bin/bash www-data -c "php occ app:enable spreed"  # Talk

# Create ExCalibur folder
su -s /bin/bash www-data -c "php occ files:scan --all"

echo "Nextcloud init complete."
```

**Step 6: Test docker-compose validates**

Run: `cd /home/andrew/projects/ex_calibur && docker-compose config --quiet`
Expected: no errors

**Step 7: Commit**

```bash
git add docker-compose.yml docker/init-nextcloud.sh
git commit -m "feat: add Nextcloud + MariaDB to docker-compose stack"
```

---

### Task 1: Nextcloud Client Module

**Files:**
- Create: `lib/ex_calibur/nextcloud/client.ex`
- Create: `test/ex_calibur/nextcloud/client_test.exs`

**Step 1: Write failing test for client**

```elixir
# test/ex_calibur/nextcloud/client_test.exs
defmodule ExCalibur.Nextcloud.ClientTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Nextcloud.Client

  describe "base_url/0" do
    test "returns configured URL" do
      assert is_binary(Client.base_url())
    end
  end

  describe "auth_headers/0" do
    test "returns basic auth header" do
      headers = Client.auth_headers()
      assert [{"authorization", "Basic " <> _}] = headers
    end
  end

  describe "webdav_url/1" do
    test "builds path under remote.php/dav/files" do
      url = Client.webdav_url("/Documents/test.md")
      assert String.contains?(url, "remote.php/dav/files/")
      assert String.ends_with?(url, "/Documents/test.md")
    end
  end

  describe "ocs_url/1" do
    test "builds OCS API path" do
      url = Client.ocs_url("/apps/notes/api/v1/notes")
      assert String.contains?(url, "ocs/v2.php")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_calibur/nextcloud/client_test.exs`
Expected: compilation error — module not found

**Step 3: Implement Client module**

```elixir
# lib/ex_calibur/nextcloud/client.ex
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

    case Req.request(method: :propfind, url: url, headers: auth_headers() ++ [{"depth", depth}, {"content-type", "application/xml"}], body: body) do
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

    case Req.request(method: :mkcol, url: url, headers: auth_headers()) do
      {:ok, %{status: status}} when status in [200, 201] -> :ok
      {:ok, %{status: 405}} -> :ok  # already exists
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete(path) do
    url = webdav_url(path)

    case Req.delete(url, headers: auth_headers()) do
      {:ok, %{status: status}} when status in [200, 204]} -> :ok
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- OCS REST Operations ---

  def ocs_get(path) do
    url = ocs_url(path)

    case Req.get(url, headers: auth_headers() ++ [{"ocs-apirequest", "true"}, {"accept", "application/json"}]) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def ocs_post(path, body) do
    url = ocs_url(path)

    case Req.post(url, headers: auth_headers() ++ [{"ocs-apirequest", "true"}, {"accept", "application/json"}, {"content-type", "application/json"}], json: body) do
      {:ok, %{status: status, body: resp}} when status in [200, 201] -> {:ok, resp}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Notes API (convenience wrappers) ---

  def list_notes do
    case Req.get("#{base_url()}/index.php/apps/notes/api/v1/notes", headers: auth_headers() ++ [{"accept", "application/json"}]) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_note(title, content, category \\ "") do
    case Req.post("#{base_url()}/index.php/apps/notes/api/v1/notes",
      headers: auth_headers() ++ [{"content-type", "application/json"}, {"accept", "application/json"}],
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
    # Simple regex-based parser for WebDAV multistatus responses
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
```

**Step 4: Run tests**

Run: `mix test test/ex_calibur/nextcloud/client_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_calibur/nextcloud/client.ex test/ex_calibur/nextcloud/client_test.exs
git commit -m "feat: add Nextcloud client module with WebDAV, OCS, Notes, Talk, Activity APIs"
```

---

### Task 2: Nextcloud Watcher Source

**Files:**
- Create: `lib/ex_calibur/sources/nextcloud_watcher.ex`
- Create: `test/ex_calibur/sources/nextcloud_watcher_test.exs`
- Modify: `lib/ex_calibur/sources/source.ex` (add "nextcloud" to valid types)
- Modify: `lib/ex_calibur/sources/source_worker.ex` (add source_module clause)

**Step 1: Write failing test**

```elixir
# test/ex_calibur/sources/nextcloud_watcher_test.exs
defmodule ExCalibur.Sources.NextcloudWatcherTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Sources.NextcloudWatcher

  describe "init/1" do
    test "initializes with last_activity_id from config" do
      assert {:ok, %{last_activity_id: 0}} = NextcloudWatcher.init(%{})
    end

    test "restores last_activity_id from state" do
      assert {:ok, %{last_activity_id: 42}} = NextcloudWatcher.init(%{"last_activity_id" => 42})
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_calibur/sources/nextcloud_watcher_test.exs`
Expected: compilation error

**Step 3: Implement NextcloudWatcher**

```elixir
# lib/ex_calibur/sources/nextcloud_watcher.ex
defmodule ExCalibur.Sources.NextcloudWatcher do
  @moduledoc false
  @behaviour ExCalibur.Sources.Behaviour

  alias ExCalibur.Nextcloud.Client
  alias ExCalibur.Sources.SourceItem

  require Logger

  @impl true
  def init(config) do
    last_id = config["last_activity_id"] || 0
    {:ok, %{last_activity_id: last_id}}
  end

  @impl true
  def fetch(state, config) do
    type_filter = config["activity_types"] || ["file_created", "file_changed", "calendar_todo", "spreed"]

    case Client.activity(state.last_activity_id) do
      {:ok, %{"ocs" => %{"data" => activities}}} when is_list(activities) ->
        filtered =
          activities
          |> Enum.filter(fn a -> a["type"] in type_filter end)
          |> Enum.map(&activity_to_item(config, &1))

        new_last_id =
          case activities do
            [latest | _] -> latest["activity_id"] || state.last_activity_id
            [] -> state.last_activity_id
          end

        {:ok, filtered, %{last_activity_id: new_last_id}}

      {:ok, _other} ->
        {:ok, [], state}

      {:error, reason} ->
        Logger.warning("[NextcloudWatcher] Activity fetch failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp activity_to_item(config, activity) do
    source_id = config["source_id"] || "nextcloud"

    %SourceItem{
      source_id: source_id,
      type: "nextcloud_activity",
      content: format_activity(activity),
      metadata: %{
        activity_id: activity["activity_id"],
        activity_type: activity["type"],
        subject: activity["subject"],
        user: activity["user"],
        datetime: activity["datetime"]
      }
    }
  end

  defp format_activity(activity) do
    """
    ## Nextcloud Activity
    **Type:** #{activity["type"]}
    **Subject:** #{activity["subject"]}
    **User:** #{activity["user"]}
    **Date:** #{activity["datetime"]}
    """
  end
end
```

**Step 4: Add "nextcloud" to source.ex valid types**

In `lib/ex_calibur/sources/source.ex`, add `"nextcloud"` to the `validate_inclusion` list:

```elixir
~w(git directory feed webhook url websocket lodge obsidian email media github_issues nextcloud)
```

**Step 5: Add source_module clause to source_worker.ex**

In `lib/ex_calibur/sources/source_worker.ex`, add after the `github_issues` clause:

```elixir
defp source_module("nextcloud"), do: ExCalibur.Sources.NextcloudWatcher
```

**Step 6: Run tests**

Run: `mix test test/ex_calibur/sources/nextcloud_watcher_test.exs`
Expected: PASS

**Step 7: Commit**

```bash
git add lib/ex_calibur/sources/nextcloud_watcher.ex test/ex_calibur/sources/nextcloud_watcher_test.exs lib/ex_calibur/sources/source.ex lib/ex_calibur/sources/source_worker.ex
git commit -m "feat: add Nextcloud Activity watcher source type"
```

---

### Task 3: Nextcloud Books (Source Blueprints)

**Files:**
- Modify: `lib/ex_calibur/sources/book.ex`

**Step 1: Add Nextcloud books to book.ex**

Add these four books to the `books()` function list:

```elixir
%Book{
  id: "nextcloud_file_watcher",
  name: "Nextcloud File Watcher",
  description: "Watch a Nextcloud folder for file changes via Activity API. Triggers on file create/update events.",
  source_type: "nextcloud",
  default_config: %{
    "interval" => 30_000,
    "activity_types" => ["file_created", "file_changed", "file_deleted"]
  },
  suggested_guild: "Code Review",
  kind: :book
},
%Book{
  id: "nextcloud_talk_source",
  name: "Nextcloud Talk Source",
  description: "Feed Nextcloud Talk chat messages into guild evaluation. Watches for new messages across channels.",
  source_type: "nextcloud",
  default_config: %{
    "interval" => 30_000,
    "activity_types" => ["spreed"]
  },
  suggested_guild: "Content Moderation",
  kind: :book
},
%Book{
  id: "nextcloud_calendar_source",
  name: "Nextcloud Calendar Source",
  description: "Watch Nextcloud Calendar for new/updated events. Provides upcoming events as agent context.",
  source_type: "nextcloud",
  default_config: %{
    "interval" => 60_000,
    "activity_types" => ["calendar_todo", "calendar"]
  },
  suggested_guild: "Everyday Council",
  kind: :book
},
%Book{
  id: "nextcloud_notes_source",
  name: "Nextcloud Notes Source",
  description: "Watch Nextcloud Notes for new or updated notes. Feeds note content into guild evaluation.",
  source_type: "nextcloud",
  default_config: %{
    "interval" => 60_000,
    "activity_types" => ["file_created", "file_changed"]
  },
  suggested_guild: "Everyday Council",
  kind: :book
}
```

**Step 2: Run full test suite to verify no breakage**

Run: `mix test`
Expected: PASS (no regressions)

**Step 3: Commit**

```bash
git add lib/ex_calibur/sources/book.ex
git commit -m "feat: add Nextcloud book blueprints (files, talk, calendar, notes)"
```

---

### Task 4: Safe Tools — search_nextcloud, read_nextcloud, read_nextcloud_notes

**Files:**
- Create: `lib/ex_calibur/tools/search_nextcloud.ex`
- Create: `lib/ex_calibur/tools/read_nextcloud.ex`
- Create: `lib/ex_calibur/tools/read_nextcloud_notes.ex`
- Create: `test/ex_calibur/tools/search_nextcloud_test.exs`
- Create: `test/ex_calibur/tools/read_nextcloud_test.exs`
- Create: `test/ex_calibur/tools/read_nextcloud_notes_test.exs`
- Modify: `lib/ex_calibur/tools/registry.ex`

**Step 1: Write failing test for search_nextcloud**

```elixir
# test/ex_calibur/tools/search_nextcloud_test.exs
defmodule ExCalibur.Tools.SearchNextcloudTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Tools.SearchNextcloud

  test "req_llm_tool returns a valid tool struct" do
    tool = SearchNextcloud.req_llm_tool()
    assert tool.name == "search_nextcloud"
    assert is_binary(tool.description)
    assert is_map(tool.parameter_schema)
  end
end
```

**Step 2: Implement search_nextcloud**

```elixir
# lib/ex_calibur/tools/search_nextcloud.ex
defmodule ExCalibur.Tools.SearchNextcloud do
  @moduledoc false

  alias ExCalibur.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "search_nextcloud",
      description: "Search and list files in Nextcloud by path. Returns file listing for a directory.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Directory path to list, e.g. '/Documents' or '/ExCalibur'. Defaults to root."
          }
        }
      },
      callback: &call/1
    )
  end

  def call(params) do
    path = params["path"] || "/"

    case Client.propfind(path) do
      {:ok, entries} ->
        {:ok, Enum.join(entries, "\n")}

      {:error, reason} ->
        {:error, "Failed to list Nextcloud path #{path}: #{inspect(reason)}"}
    end
  end
end
```

**Step 3: Write failing test for read_nextcloud**

```elixir
# test/ex_calibur/tools/read_nextcloud_test.exs
defmodule ExCalibur.Tools.ReadNextcloudTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Tools.ReadNextcloud

  test "req_llm_tool returns a valid tool struct" do
    tool = ReadNextcloud.req_llm_tool()
    assert tool.name == "read_nextcloud"
    assert is_binary(tool.description)
  end
end
```

**Step 4: Implement read_nextcloud**

```elixir
# lib/ex_calibur/tools/read_nextcloud.ex
defmodule ExCalibur.Tools.ReadNextcloud do
  @moduledoc false

  alias ExCalibur.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_nextcloud",
      description: "Read a file from Nextcloud by path. Returns the file content as text.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Full file path in Nextcloud, e.g. '/Documents/report.md'"
          }
        },
        "required" => ["path"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path}) do
    case Client.get_file(path) do
      {:ok, content} when is_binary(content) ->
        truncated = String.slice(content, 0, 8000)
        {:ok, truncated}

      {:error, :not_found} ->
        {:error, "File not found: #{path}"}

      {:error, reason} ->
        {:error, "Failed to read #{path}: #{inspect(reason)}"}
    end
  end
end
```

**Step 5: Write failing test for read_nextcloud_notes**

```elixir
# test/ex_calibur/tools/read_nextcloud_notes_test.exs
defmodule ExCalibur.Tools.ReadNextcloudNotesTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Tools.ReadNextcloudNotes

  test "req_llm_tool returns a valid tool struct" do
    tool = ReadNextcloudNotes.req_llm_tool()
    assert tool.name == "read_nextcloud_notes"
    assert is_binary(tool.description)
  end
end
```

**Step 6: Implement read_nextcloud_notes**

```elixir
# lib/ex_calibur/tools/read_nextcloud_notes.ex
defmodule ExCalibur.Tools.ReadNextcloudNotes do
  @moduledoc false

  alias ExCalibur.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_nextcloud_notes",
      description: "List and search Nextcloud Notes. Returns note titles and content. Optionally filter by search term.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "search" => %{
            "type" => "string",
            "description" => "Optional search term to filter notes by title or content"
          }
        }
      },
      callback: &call/1
    )
  end

  def call(params) do
    search = params["search"]

    case Client.list_notes() do
      {:ok, notes} when is_list(notes) ->
        filtered =
          if search do
            term = String.downcase(search)

            Enum.filter(notes, fn note ->
              String.contains?(String.downcase(note["title"] || ""), term) or
                String.contains?(String.downcase(note["content"] || ""), term)
            end)
          else
            notes
          end

        formatted =
          filtered
          |> Enum.take(20)
          |> Enum.map_join("\n---\n", fn note ->
            "## #{note["title"]}\n#{String.slice(note["content"] || "", 0, 2000)}"
          end)

        {:ok, formatted}

      {:error, reason} ->
        {:error, "Failed to list notes: #{inspect(reason)}"}
    end
  end
end
```

**Step 7: Register tools in registry.ex**

Add aliases at top of `lib/ex_calibur/tools/registry.ex`:

```elixir
alias ExCalibur.Tools.ReadNextcloud
alias ExCalibur.Tools.ReadNextcloudNotes
alias ExCalibur.Tools.SearchNextcloud
```

Add to `@safe` list:

```elixir
SearchNextcloud,
ReadNextcloud,
ReadNextcloudNotes
```

**Step 8: Run all tool tests**

Run: `mix test test/ex_calibur/tools/`
Expected: PASS

**Step 9: Commit**

```bash
git add lib/ex_calibur/tools/search_nextcloud.ex lib/ex_calibur/tools/read_nextcloud.ex lib/ex_calibur/tools/read_nextcloud_notes.ex test/ex_calibur/tools/search_nextcloud_test.exs test/ex_calibur/tools/read_nextcloud_test.exs test/ex_calibur/tools/read_nextcloud_notes_test.exs lib/ex_calibur/tools/registry.ex
git commit -m "feat: add safe Nextcloud tools (search, read file, read notes)"
```

---

### Task 5: Write Tools — write_nextcloud, create_nextcloud_note, nextcloud_calendar

**Files:**
- Create: `lib/ex_calibur/tools/write_nextcloud.ex`
- Create: `lib/ex_calibur/tools/create_nextcloud_note.ex`
- Create: `lib/ex_calibur/tools/nextcloud_calendar.ex`
- Create: `test/ex_calibur/tools/write_nextcloud_test.exs`
- Create: `test/ex_calibur/tools/create_nextcloud_note_test.exs`  (name collision with obsidian — use `create_nextcloud_note`)
- Create: `test/ex_calibur/tools/nextcloud_calendar_test.exs`
- Modify: `lib/ex_calibur/tools/registry.ex`

**Step 1: Implement write_nextcloud**

```elixir
# lib/ex_calibur/tools/write_nextcloud.ex
defmodule ExCalibur.Tools.WriteNextcloud do
  @moduledoc false

  alias ExCalibur.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "write_nextcloud",
      description: "Write or create a file in Nextcloud. Creates parent directories automatically.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Full file path in Nextcloud, e.g. '/ExCalibur/reports/summary.md'"
          },
          "content" => %{
            "type" => "string",
            "description" => "File content to write"
          }
        },
        "required" => ["path", "content"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path, "content" => content}) do
    # Ensure parent directories exist
    path
    |> Path.dirname()
    |> ensure_dirs()

    case Client.put_file(path, content) do
      :ok -> {:ok, "Wrote #{byte_size(content)} bytes to #{path}"}
      {:error, reason} -> {:error, "Failed to write #{path}: #{inspect(reason)}"}
    end
  end

  defp ensure_dirs("/"), do: :ok

  defp ensure_dirs(path) do
    parts = path |> String.split("/", trim: true)

    Enum.reduce(parts, "", fn part, acc ->
      dir = "#{acc}/#{part}"
      Client.mkcol(dir)
      dir
    end)
  end
end
```

**Step 2: Implement create_nextcloud_note**

```elixir
# lib/ex_calibur/tools/create_nextcloud_note.ex
defmodule ExCalibur.Tools.CreateNextcloudNote do
  @moduledoc false

  alias ExCalibur.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "create_nextcloud_note",
      description: "Create a new note in Nextcloud Notes app.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "title" => %{
            "type" => "string",
            "description" => "Note title"
          },
          "content" => %{
            "type" => "string",
            "description" => "Note content (markdown supported)"
          },
          "category" => %{
            "type" => "string",
            "description" => "Optional category/folder for the note"
          }
        },
        "required" => ["title", "content"]
      },
      callback: &call/1
    )
  end

  def call(%{"title" => title, "content" => content} = params) do
    category = params["category"] || ""

    case Client.create_note(title, content, category) do
      {:ok, note} ->
        {:ok, "Created note '#{title}' (id: #{note["id"]})"}

      {:error, reason} ->
        {:error, "Failed to create note: #{inspect(reason)}"}
    end
  end
end
```

**Step 3: Implement nextcloud_calendar**

```elixir
# lib/ex_calibur/tools/nextcloud_calendar.ex
defmodule ExCalibur.Tools.NextcloudCalendar do
  @moduledoc false

  alias ExCalibur.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "nextcloud_calendar",
      description: "Create a calendar event in Nextcloud or list upcoming events.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "action" => %{
            "type" => "string",
            "enum" => ["create", "list"],
            "description" => "Action to perform: 'create' a new event or 'list' upcoming events"
          },
          "title" => %{
            "type" => "string",
            "description" => "Event title (required for create)"
          },
          "start" => %{
            "type" => "string",
            "description" => "Start datetime in ISO 8601 format, e.g. '2026-03-15T10:00:00' (required for create)"
          },
          "end" => %{
            "type" => "string",
            "description" => "End datetime in ISO 8601 format (required for create)"
          },
          "description" => %{
            "type" => "string",
            "description" => "Optional event description"
          }
        },
        "required" => ["action"]
      },
      callback: &call/1
    )
  end

  def call(%{"action" => "create", "title" => title, "start" => start_dt, "end" => end_dt} = params) do
    desc = params["description"] || ""
    uid = "excalibur-#{System.unique_integer([:positive])}"

    vevent = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//ExCalibur//EN
    BEGIN:VEVENT
    UID:#{uid}
    DTSTART:#{format_caldav_dt(start_dt)}
    DTEND:#{format_caldav_dt(end_dt)}
    SUMMARY:#{title}
    DESCRIPTION:#{desc}
    END:VEVENT
    END:VCALENDAR
    """

    url = Client.webdav_url("") |> String.replace("/files/#{Client.username()}", "/calendars/#{Client.username()}/personal/#{uid}.ics")

    case Req.put(url, headers: Client.auth_headers() ++ [{"content-type", "text/calendar"}], body: vevent) do
      {:ok, %{status: status}} when status in [200, 201, 204] ->
        {:ok, "Created calendar event '#{title}' from #{start_dt} to #{end_dt}"}

      {:ok, %{status: status}} ->
        {:error, "Failed to create event (HTTP #{status})"}

      {:error, reason} ->
        {:error, "Failed to create event: #{inspect(reason)}"}
    end
  end

  def call(%{"action" => "list"}) do
    # Use CalDAV REPORT to get upcoming events
    url = Client.webdav_url("") |> String.replace("/files/#{Client.username()}", "/calendars/#{Client.username()}/personal")

    now = Calendar.strftime(DateTime.utc_now(), "%Y%m%dT%H%M%SZ")

    body = """
    <?xml version="1.0"?>
    <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
      <d:prop>
        <d:getetag/>
        <c:calendar-data/>
      </d:prop>
      <c:filter>
        <c:comp-filter name="VCALENDAR">
          <c:comp-filter name="VEVENT">
            <c:time-range start="#{now}"/>
          </c:comp-filter>
        </c:comp-filter>
      </c:filter>
    </c:calendar-query>
    """

    case Req.request(method: :report, url: url, headers: Client.auth_headers() ++ [{"depth", "1"}, {"content-type", "application/xml"}], body: body) do
      {:ok, %{status: status, body: resp}} when status in [200, 207] ->
        {:ok, parse_calendar_response(resp)}

      {:ok, %{status: status}} ->
        {:error, "Failed to list events (HTTP #{status})"}

      {:error, reason} ->
        {:error, "Failed to list events: #{inspect(reason)}"}
    end
  end

  defp format_caldav_dt(iso_string) do
    iso_string
    |> String.replace(~r/[-:]/, "")
    |> String.replace(~r/\.\d+/, "")
    |> then(fn s -> if String.ends_with?(s, "Z"), do: s, else: s <> "Z" end)
  end

  defp parse_calendar_response(body) when is_binary(body) do
    ~r/SUMMARY:([^\r\n]+)/
    |> Regex.scan(body)
    |> Enum.map_join("\n", fn [_, summary] -> "- #{summary}" end)
    |> then(fn
      "" -> "No upcoming events."
      events -> "Upcoming events:\n#{events}"
    end)
  end

  defp parse_calendar_response(_), do: "No upcoming events."
end
```

**Step 4: Write tests for all three**

```elixir
# test/ex_calibur/tools/write_nextcloud_test.exs
defmodule ExCalibur.Tools.WriteNextcloudTest do
  use ExUnit.Case, async: true
  test "req_llm_tool returns a valid tool struct" do
    tool = ExCalibur.Tools.WriteNextcloud.req_llm_tool()
    assert tool.name == "write_nextcloud"
    assert "path" in tool.parameter_schema["required"]
  end
end
```

```elixir
# test/ex_calibur/tools/create_nextcloud_note_test.exs
defmodule ExCalibur.Tools.CreateNextcloudNoteTest do
  use ExUnit.Case, async: true
  test "req_llm_tool returns a valid tool struct" do
    tool = ExCalibur.Tools.CreateNextcloudNote.req_llm_tool()
    assert tool.name == "create_nextcloud_note"
    assert "title" in tool.parameter_schema["required"]
  end
end
```

```elixir
# test/ex_calibur/tools/nextcloud_calendar_test.exs
defmodule ExCalibur.Tools.NextcloudCalendarTest do
  use ExUnit.Case, async: true
  test "req_llm_tool returns a valid tool struct" do
    tool = ExCalibur.Tools.NextcloudCalendar.req_llm_tool()
    assert tool.name == "nextcloud_calendar"
    assert "action" in tool.parameter_schema["required"]
  end
end
```

**Step 5: Register in registry.ex**

Add aliases:

```elixir
alias ExCalibur.Tools.CreateNextcloudNote
alias ExCalibur.Tools.NextcloudCalendar
alias ExCalibur.Tools.WriteNextcloud
```

Add to `@write` list:

```elixir
WriteNextcloud,
CreateNextcloudNote,
NextcloudCalendar
```

**Step 6: Run tests**

Run: `mix test test/ex_calibur/tools/`
Expected: PASS

**Step 7: Commit**

```bash
git add lib/ex_calibur/tools/write_nextcloud.ex lib/ex_calibur/tools/create_nextcloud_note.ex lib/ex_calibur/tools/nextcloud_calendar.ex test/ex_calibur/tools/write_nextcloud_test.exs test/ex_calibur/tools/create_nextcloud_note_test.exs test/ex_calibur/tools/nextcloud_calendar_test.exs lib/ex_calibur/tools/registry.ex
git commit -m "feat: add write Nextcloud tools (write file, create note, calendar)"
```

---

### Task 6: Dangerous Tool — nextcloud_talk

**Files:**
- Create: `lib/ex_calibur/tools/nextcloud_talk.ex`
- Create: `test/ex_calibur/tools/nextcloud_talk_test.exs`
- Modify: `lib/ex_calibur/tools/registry.ex`

**Step 1: Implement nextcloud_talk**

```elixir
# lib/ex_calibur/tools/nextcloud_talk.ex
defmodule ExCalibur.Tools.NextcloudTalk do
  @moduledoc false

  alias ExCalibur.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "nextcloud_talk",
      description: "Send a message to a Nextcloud Talk channel or list available channels.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "action" => %{
            "type" => "string",
            "enum" => ["send", "list_rooms"],
            "description" => "Action: 'send' a message or 'list_rooms' to see available channels"
          },
          "room_token" => %{
            "type" => "string",
            "description" => "Talk room token (required for send)"
          },
          "message" => %{
            "type" => "string",
            "description" => "Message to send (required for send)"
          }
        },
        "required" => ["action"]
      },
      callback: &call/1
    )
  end

  def call(%{"action" => "send", "room_token" => token, "message" => message}) do
    case Client.talk_send(token, message) do
      {:ok, _} -> {:ok, "Message sent to room #{token}"}
      {:error, reason} -> {:error, "Failed to send message: #{inspect(reason)}"}
    end
  end

  def call(%{"action" => "list_rooms"}) do
    case Client.talk_rooms() do
      {:ok, %{"ocs" => %{"data" => rooms}}} when is_list(rooms) ->
        formatted =
          rooms
          |> Enum.map_join("\n", fn r -> "- #{r["displayName"]} (token: #{r["token"]})" end)

        {:ok, "Talk rooms:\n#{formatted}"}

      {:error, reason} ->
        {:error, "Failed to list rooms: #{inspect(reason)}"}
    end
  end
end
```

**Step 2: Write test**

```elixir
# test/ex_calibur/tools/nextcloud_talk_test.exs
defmodule ExCalibur.Tools.NextcloudTalkTest do
  use ExUnit.Case, async: true
  test "req_llm_tool returns a valid tool struct" do
    tool = ExCalibur.Tools.NextcloudTalk.req_llm_tool()
    assert tool.name == "nextcloud_talk"
    assert "action" in tool.parameter_schema["required"]
  end
end
```

**Step 3: Register in registry.ex**

Add alias:

```elixir
alias ExCalibur.Tools.NextcloudTalk
```

Add to `@dangerous` list:

```elixir
NextcloudTalk
```

**Step 4: Run tests**

Run: `mix test test/ex_calibur/tools/`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_calibur/tools/nextcloud_talk.ex test/ex_calibur/tools/nextcloud_talk_test.exs lib/ex_calibur/tools/registry.ex
git commit -m "feat: add Nextcloud Talk tool (dangerous tier)"
```

---

### Task 7: Output Sink

**Files:**
- Create: `lib/ex_calibur/nextcloud/sink.ex`
- Create: `test/ex_calibur/nextcloud/sink_test.exs`

**Step 1: Write failing test**

```elixir
# test/ex_calibur/nextcloud/sink_test.exs
defmodule ExCalibur.Nextcloud.SinkTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Nextcloud.Sink

  describe "quest_path/2" do
    test "builds correct path from quest name and date" do
      path = Sink.quest_path("Code Review", ~D[2026-03-12])
      assert path == "/ExCalibur/quests/code-review/2026-03-12.md"
    end
  end

  describe "format_outcome/2" do
    test "formats quest outcome as markdown" do
      outcome = Sink.format_outcome("Code Review", "All looks good, no issues found.")
      assert String.contains?(outcome, "# Code Review")
      assert String.contains?(outcome, "All looks good")
    end
  end
end
```

**Step 2: Implement Sink**

```elixir
# lib/ex_calibur/nextcloud/sink.ex
defmodule ExCalibur.Nextcloud.Sink do
  @moduledoc false

  alias ExCalibur.Nextcloud.Client

  require Logger

  def write_quest_outcome(quest_name, outcome, opts \\ []) do
    date = opts[:date] || Date.utc_today()
    path = quest_path(quest_name, date)
    content = format_outcome(quest_name, outcome)

    # Ensure directory structure
    Client.mkcol("/ExCalibur")
    Client.mkcol("/ExCalibur/quests")
    Client.mkcol("/ExCalibur/quests/#{slugify(quest_name)}")

    case Client.put_file(path, content) do
      :ok ->
        maybe_notify_talk(quest_name, outcome, opts)
        Logger.info("[Nextcloud.Sink] Wrote quest outcome to #{path}")
        :ok

      {:error, reason} ->
        Logger.warning("[Nextcloud.Sink] Failed to write outcome: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def quest_path(quest_name, date) do
    "/ExCalibur/quests/#{slugify(quest_name)}/#{Date.to_iso8601(date)}.md"
  end

  def format_outcome(quest_name, outcome) do
    now = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M UTC")

    """
    # #{quest_name}

    **Generated:** #{now}

    ---

    #{outcome}
    """
  end

  defp maybe_notify_talk(_quest_name, _outcome, opts) do
    case opts[:talk_room] do
      nil -> :ok
      token ->
        summary = String.slice(opts[:outcome] || "", 0, 500)
        Client.talk_send(token, "Quest complete: #{opts[:quest_name]}\n\n#{summary}")
    end
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
```

**Step 3: Run tests**

Run: `mix test test/ex_calibur/nextcloud/sink_test.exs`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/ex_calibur/nextcloud/sink.ex test/ex_calibur/nextcloud/sink_test.exs
git commit -m "feat: add Nextcloud output sink for quest outcomes"
```

---

### Task 8: Integration Wiring

**Files:**
- Modify: `lib/ex_calibur/settings.ex` (add Nextcloud settings)
- Modify: `lib/ex_calibur_web/live/settings_live.ex` (add Nextcloud config section)

**Step 1: Add Nextcloud settings helpers**

Add to `lib/ex_calibur/settings.ex` — no new functions needed since `get/1` and `put/2` are generic. Just document the keys:
- `:nextcloud_url`
- `:nextcloud_user`
- `:nextcloud_password`
- `:nextcloud_talk_room` (default room for sink notifications)

**Step 2: Add Nextcloud section to settings_live.ex**

Add a "Nextcloud" section to the settings form with fields for URL, username, password, and default Talk room. Follow the existing pattern for other settings fields.

**Step 3: Run full test suite**

Run: `mix test`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/ex_calibur/settings.ex lib/ex_calibur_web/live/settings_live.ex
git commit -m "feat: add Nextcloud settings to Settings UI"
```

---

### Task 9: Nextcloud OAuth2 Auth + Role-Based Access

**Files:**
- Add dep: `mix.exs` (add `ueberauth`, `ueberauth_oidc` or `oauth2`)
- Create: `lib/ex_calibur_web/auth.ex` (auth plug + role helpers)
- Create: `lib/ex_calibur_web/controllers/auth_controller.ex` (OAuth callback)
- Modify: `lib/ex_calibur_web/router.ex` (add auth routes, protect existing routes)
- Create: `lib/ex_calibur/accounts.ex` (user schema + role mapping)
- Create: `lib/ex_calibur/accounts/user.ex` (Ecto schema)
- Create: `priv/repo/migrations/*_create_users.exs`
- Modify: `docker/init-nextcloud.sh` (enable OIDC app, create groups)

**Step 1: Add dependencies to mix.exs**

```elixir
{:oauth2, "~> 2.1"}
```

**Step 2: Create user schema + migration**

```elixir
# lib/ex_calibur/accounts/user.ex
defmodule ExCalibur.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :nextcloud_id, :string
    field :username, :string
    field :display_name, :string
    field :role, :string, default: "user"  # "super_admin", "admin", "user"
    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:nextcloud_id, :username, :display_name, :role])
    |> validate_required([:nextcloud_id, :username, :role])
    |> validate_inclusion(:role, ~w(super_admin admin user))
    |> unique_constraint(:nextcloud_id)
  end
end
```

Migration:

```elixir
defmodule ExCalibur.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :nextcloud_id, :string, null: false
      add :username, :string, null: false
      add :display_name, :string
      add :role, :string, null: false, default: "user"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:nextcloud_id])
  end
end
```

**Step 3: Create Accounts context**

```elixir
# lib/ex_calibur/accounts.ex
defmodule ExCalibur.Accounts do
  import Ecto.Query
  alias ExCalibur.Repo
  alias ExCalibur.Accounts.User

  def get_or_create_from_nextcloud(userinfo) do
    nc_id = to_string(userinfo["sub"] || userinfo["id"])

    case Repo.get_by(User, nextcloud_id: nc_id) do
      nil ->
        role = role_from_groups(userinfo["groups"] || [])
        %User{}
        |> User.changeset(%{
          nextcloud_id: nc_id,
          username: userinfo["preferred_username"] || userinfo["id"],
          display_name: userinfo["name"] || userinfo["preferred_username"],
          role: role
        })
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  def get_user(id), do: Repo.get(User, id)

  defp role_from_groups(groups) do
    cond do
      "excalibur-super-admin" in groups -> "super_admin"
      "excalibur-admin" in groups -> "admin"
      true -> "user"
    end
  end
end
```

**Step 4: Create OAuth2 client + auth controller**

```elixir
# lib/ex_calibur_web/controllers/auth_controller.ex
defmodule ExCaliburWeb.AuthController do
  use ExCaliburWeb, :controller

  alias ExCalibur.Accounts

  def login(conn, _params) do
    client = oauth_client()
    authorize_url = OAuth2.Client.authorize_url!(client)
    redirect(conn, external: authorize_url)
  end

  def callback(conn, %{"code" => code}) do
    client = oauth_client()

    with {:ok, client} <- OAuth2.Client.get_token(client, code: code),
         {:ok, %{body: userinfo}} <- OAuth2.Client.get(client, "/ocs/v2.php/cloud/user?format=json"),
         {:ok, user} <- Accounts.get_or_create_from_nextcloud(userinfo) do
      conn
      |> put_session(:user_id, user.id)
      |> redirect(to: "/")
    else
      _ ->
        conn
        |> put_flash(:error, "Authentication failed")
        |> redirect(to: "/login")
    end
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/login")
  end

  defp oauth_client do
    nc_url = ExCalibur.Nextcloud.Client.base_url()

    OAuth2.Client.new(
      strategy: OAuth2.Strategy.AuthCode,
      client_id: System.get_env("NEXTCLOUD_OAUTH_CLIENT_ID", "excalibur"),
      client_secret: System.get_env("NEXTCLOUD_OAUTH_CLIENT_SECRET", "excalibur-secret"),
      site: nc_url,
      authorize_url: "#{nc_url}/index.php/apps/oauth2/authorize",
      token_url: "#{nc_url}/index.php/apps/oauth2/api/v1/token",
      redirect_uri: "#{ExCaliburWeb.Endpoint.url()}/auth/callback"
    )
  end
end
```

**Step 5: Create auth plug**

```elixir
# lib/ex_calibur_web/auth.ex
defmodule ExCaliburWeb.Auth do
  import Plug.Conn
  import Phoenix.Controller

  def require_auth(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        conn |> redirect(to: "/login") |> halt()
      user_id ->
        user = ExCalibur.Accounts.get_user(user_id)
        assign(conn, :current_user, user)
    end
  end

  def require_role(conn, roles) when is_list(roles) do
    if conn.assigns[:current_user] && conn.assigns.current_user.role in roles do
      conn
    else
      conn |> put_status(403) |> text("Forbidden") |> halt()
    end
  end

  def require_admin(conn, _opts), do: require_role(conn, ["super_admin", "admin"])
  def require_super_admin(conn, _opts), do: require_role(conn, ["super_admin"])
end
```

**Step 6: Update router.ex**

Add auth routes and protect existing routes with role-based pipelines:
- `/login`, `/auth/callback`, `/auth/logout` — public
- `/settings` — super_admin only
- `/guild-hall`, `/members`, `/quests` — admin+
- `/lodge`, `/library`, `/evaluate` — all authenticated users

**Step 6b: Add tool-tier gating per role**

Modify `ExCalibur.Tools.Registry.resolve_tools/1` to accept a user role and cap tool tier:
- `super_admin` → all tools (dangerous)
- `admin` → safe + write tools
- `user` → safe tools only

This prevents Jude from triggering quests that use dangerous tools (close_issue, merge_pr, send_email, etc.). The quest runner should pass the current user's role through to the step runner, which passes it to `resolve_tools/1`. When no user context (scheduled/source-triggered quests), default to the step's configured tier.

**Step 7: Update init-nextcloud.sh**

Add group creation and OAuth2 client registration:

```bash
# Create groups for role mapping
su -s /bin/bash www-data -c "php occ group:add excalibur-super-admin"
su -s /bin/bash www-data -c "php occ group:add excalibur-admin"
su -s /bin/bash www-data -c "php occ group:add excalibur-user"

# Add admin to super-admin group
su -s /bin/bash www-data -c "php occ group:adduser excalibur-super-admin admin"
```

**Step 8: Run migration and test**

Run: `mix ecto.migrate && mix test`
Expected: PASS

**Step 9: Commit**

```bash
git add mix.exs lib/ex_calibur/accounts.ex lib/ex_calibur/accounts/user.ex lib/ex_calibur_web/auth.ex lib/ex_calibur_web/controllers/auth_controller.ex lib/ex_calibur_web/router.ex priv/repo/migrations/*_create_users.exs docker/init-nextcloud.sh
git commit -m "feat: add Nextcloud OAuth2 auth with role-based access (super_admin, admin, user)"
```
