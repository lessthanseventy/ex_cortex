# Tool Expansion & Obsidian Knowledge Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Expand ExCalibur from 3 tools to 29, add Obsidian as a durable knowledge layer, create a settings UI, wire all guilds to appropriate tools, and add 3 new source types.

**Architecture:** Each tool is a module returning a ReqLLM.Tool struct, registered in a three-tier registry (safe/write/dangerous). Obsidian syncs from Postgres as a side effect of every write. Settings stored in a jsonb column. Guild charters updated with per-member tool assignments.

**Tech Stack:** Elixir/Phoenix, ReqLLM, obsidian-cli, gh, notmuch, msmtp, jq, pdftotext, pandoc, w3m, ddgr, yt-dlp, ffmpeg, ImageMagick

**Design Doc:** docs/plans/2026-03-12-tool-expansion-design.md

---

## Dependency Graph

```
Task 0: Registry refactor ─────────────────┐
Task 1: Settings config ──────────────┐     │
                                      │     │
Task 2: Obsidian tools ◄──────────────┼─────┤
Task 3: Email tools ◄─────────────────┼─────┤
Task 4: GitHub tools ◄────────────────┼─────┤
Task 5: Data processing tools ◄───────┼─────┤
Task 6: Web tools ◄───────────────────┼─────┘
Task 7: Media tools ◄─────────────────┘
Task 8: Vision tools ◄──── Task 7
Task 9: Reclassify existing ◄── Task 0
                                      │
Task 10: Obsidian sync ◄── Task 1     │
Task 11: Wire guilds ◄── Tasks 2-10 ──┘
Task 12: New sources ◄── Tasks 2,3,7,10
Task 13: Settings UI ◄── Task 1
Task 14: Integration test ◄── Tasks 10,11,12,13
```

Parallel tracks after Tasks 0+1: Obsidian, Email, GitHub, Data, Web, Media can all be built concurrently.

---

### Task 0: Registry three-tier refactor

**Files:**
- Modify: `lib/ex_calibur/tools/registry.ex`
- Modify: `lib/ex_calibur/step_runner.ex` (lines 324-328)
- Test: `test/ex_calibur/tools/registry_test.exs`

**Step 1: Write failing test**

```elixir
# test/ex_calibur/tools/registry_test.exs
defmodule ExCalibur.Tools.RegistryTest do
  use ExUnit.Case, async: true
  alias ExCalibur.Tools.Registry

  test "resolve_tools(:all_safe) returns only safe tools" do
    tools = Registry.resolve_tools(:all_safe)
    assert Enum.all?(tools, &is_struct(&1, ReqLLM.Tool))
    names = Enum.map(tools, & &1.name)
    assert "query_lore" in names
    refute "run_quest" in names
  end

  test "resolve_tools(:write) includes safe + write tools" do
    safe = Registry.resolve_tools(:all_safe)
    write = Registry.resolve_tools(:write)
    assert length(write) >= length(safe)
  end

  test "resolve_tools(:dangerous) includes all tiers" do
    write = Registry.resolve_tools(:write)
    dangerous = Registry.resolve_tools(:dangerous)
    assert length(dangerous) >= length(write)
    names = Enum.map(dangerous, & &1.name)
    assert "run_quest" in names
  end

  test "resolve_tools(:yolo) is alias for :dangerous" do
    assert Registry.resolve_tools(:yolo) == Registry.resolve_tools(:dangerous)
  end
end
```

**Step 2: Run test, verify fail**

Run: `mix test test/ex_calibur/tools/registry_test.exs`
Expected: FAIL — :write and :dangerous not recognized

**Step 3: Refactor registry**

```elixir
# lib/ex_calibur/tools/registry.ex
defmodule ExCalibur.Tools.Registry do
  alias ExCalibur.Tools.{QueryLore, FetchUrl, RunQuest}

  @safe [QueryLore, FetchUrl]
  @write []
  @dangerous [RunQuest]

  def list_safe, do: Enum.map(@safe, & &1.tool())
  def list_write, do: Enum.map(@safe ++ @write, & &1.tool())
  def list_dangerous, do: Enum.map(@safe ++ @write ++ @dangerous, & &1.tool())

  def resolve_tools(:all_safe), do: list_safe()
  def resolve_tools(:write), do: list_write()
  def resolve_tools(:dangerous), do: list_dangerous()
  def resolve_tools(:yolo), do: list_dangerous()

  def resolve_tools(names) when is_list(names) do
    all = list_dangerous()
    Enum.filter(all, &(&1.name in names))
  end

  def get(name) do
    Enum.find(list_dangerous(), &(&1.name == name))
  end
end
```

**Step 4: Update step_runner resolve_member_tools**

```elixir
# lib/ex_calibur/step_runner.ex — replace resolve_member_tools functions
defp resolve_member_tools(nil), do: []
defp resolve_member_tools("all_safe"), do: ExCalibur.Tools.Registry.resolve_tools(:all_safe)
defp resolve_member_tools("write"), do: ExCalibur.Tools.Registry.resolve_tools(:write)
defp resolve_member_tools("dangerous"), do: ExCalibur.Tools.Registry.resolve_tools(:dangerous)
defp resolve_member_tools("yolo"), do: ExCalibur.Tools.Registry.resolve_tools(:dangerous)
defp resolve_member_tools(names) when is_list(names), do: ExCalibur.Tools.Registry.resolve_tools(names)
defp resolve_member_tools(_), do: []
```

**Step 5: Run tests, verify pass**

Run: `mix test test/ex_calibur/tools/registry_test.exs`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ex_calibur/tools/registry.ex lib/ex_calibur/step_runner.ex test/ex_calibur/tools/registry_test.exs
git commit -m "feat: three-tier tool registry (safe/write/dangerous)"
```

---

### Task 1: Tool config in Settings

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_config_to_settings.exs`
- Modify: `lib/ex_calibur/settings.ex`
- Test: `test/ex_calibur/settings_test.exs`

**Step 1: Write failing test**

```elixir
# test/ex_calibur/settings_test.exs
defmodule ExCalibur.SettingsTest do
  use ExCalibur.DataCase, async: true
  alias ExCalibur.Settings

  test "get/1 returns nil for unconfigured key" do
    assert Settings.get(:obsidian_vault) == nil
  end

  test "put/2 stores and get/1 retrieves" do
    Settings.put(:obsidian_vault, "MyVault")
    assert Settings.get(:obsidian_vault) == "MyVault"
  end

  test "put/2 overwrites existing value" do
    Settings.put(:obsidian_vault, "Old")
    Settings.put(:obsidian_vault, "New")
    assert Settings.get(:obsidian_vault) == "New"
  end
end
```

**Step 2: Run test, verify fail**

Run: `mix test test/ex_calibur/settings_test.exs`

**Step 3: Create migration**

```elixir
defmodule ExCalibur.Repo.Migrations.AddConfigToSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add :config, :map, default: %{}
    end
  end
end
```

**Step 4: Add get/1 and put/2 to Settings**

Read the existing Settings module first, then add:

```elixir
def get(key) when is_atom(key) do
  case Repo.one(from(s in Setting)) do
    nil -> nil
    setting -> get_in(setting.config || %{}, [Atom.to_string(key)])
  end
end

def put(key, value) when is_atom(key) do
  setting = Repo.one(from(s in Setting)) || %Setting{}
  config = Map.put(setting.config || %{}, Atom.to_string(key), value)
  setting
  |> Setting.changeset(%{config: config})
  |> Repo.insert_or_update()
end
```

Also add `:config` to the Setting schema and changeset.

**Step 5: Run migration, run tests**

Run: `mix ecto.migrate && mix test test/ex_calibur/settings_test.exs`

**Step 6: Commit**

```bash
git add priv/repo/migrations/ lib/ex_calibur/settings.ex test/ex_calibur/settings_test.exs
git commit -m "feat: add jsonb config column to settings for tool configuration"
```

---

### Task 2: Obsidian tools (6 tools)

**Files:**
- Create: `lib/ex_calibur/tools/search_obsidian.ex`
- Create: `lib/ex_calibur/tools/search_obsidian_content.ex`
- Create: `lib/ex_calibur/tools/read_obsidian.ex`
- Create: `lib/ex_calibur/tools/read_obsidian_frontmatter.ex`
- Create: `lib/ex_calibur/tools/create_obsidian_note.ex`
- Create: `lib/ex_calibur/tools/daily_obsidian.ex`
- Modify: `lib/ex_calibur/tools/registry.ex`
- Test: `test/ex_calibur/tools/obsidian_tools_test.exs`

All follow the same pattern — see design doc Section 2 for the example. Each tool:
1. Reads vault from `ExCalibur.Settings.get(:obsidian_vault)`
2. Builds obsidian-cli args with `--vault` flag if vault configured
3. Calls `System.cmd("obsidian-cli", args, stderr_to_stdout: true)`
4. Returns `{:ok, output}` or `{:error, error}`

Tiers: search_obsidian, search_obsidian_content, read_obsidian, read_obsidian_frontmatter → @safe. create_obsidian_note, daily_obsidian → @write.

**Commit:** `git commit -m "feat: add 6 Obsidian tools (search, read, create, daily)"`

---

### Task 3: Email tools (3 tools)

**Files:**
- Create: `lib/ex_calibur/tools/search_email.ex`
- Create: `lib/ex_calibur/tools/read_email.ex`
- Create: `lib/ex_calibur/tools/send_email.ex`
- Modify: `lib/ex_calibur/tools/registry.ex`
- Test: `test/ex_calibur/tools/email_tools_test.exs`

search_email: `System.cmd("notmuch", ["search", query, "--limit=#{limit}"])`
read_email: `System.cmd("notmuch", ["show", "--format=text", message_id])`
send_email: Build RFC822 message string, pipe via `System.cmd("msmtp", ["-a", account, to], input: message)`

Tiers: search_email, read_email → @safe. send_email → @dangerous.

**Commit:** `git commit -m "feat: add 3 email tools (search, read, send via notmuch/msmtp)"`

---

### Task 4: GitHub tools (5 tools)

**Files:**
- Create: `lib/ex_calibur/tools/search_github.ex`
- Create: `lib/ex_calibur/tools/read_github_issue.ex`
- Create: `lib/ex_calibur/tools/list_github_notifications.ex`
- Create: `lib/ex_calibur/tools/create_github_issue.ex`
- Create: `lib/ex_calibur/tools/comment_github.ex`
- Modify: `lib/ex_calibur/tools/registry.ex`
- Test: `test/ex_calibur/tools/github_tools_test.exs`

All use `System.cmd("gh", [...])`. Repo param falls back to `Settings.get(:default_repo)`.

Tiers: search_github, read_github_issue, list_github_notifications → @safe. create_github_issue, comment_github → @dangerous.

**Commit:** `git commit -m "feat: add 5 GitHub tools via gh CLI"`

---

### Task 5: Data processing tools (3 tools)

**Files:**
- Create: `lib/ex_calibur/tools/jq_query.ex`
- Create: `lib/ex_calibur/tools/read_pdf.ex`
- Create: `lib/ex_calibur/tools/convert_document.ex`
- Modify: `lib/ex_calibur/tools/registry.ex`
- Test: `test/ex_calibur/tools/data_tools_test.exs`

jq_query: `System.cmd("jq", [expression], input: json)` — important: use `input:` option, not a temp file.
read_pdf: `System.cmd("pdftotext", [path, "-"])` — the "-" means stdout.
convert_document: `System.cmd("pandoc", ["-f", from, "-t", to, path])`

All @safe.

**Commit:** `git commit -m "feat: add data processing tools (jq, pdf, pandoc)"`

---

### Task 6: Web tools (2 tools)

**Files:**
- Modify: `lib/ex_calibur/tools/fetch_url.ex` → upgrade or create `lib/ex_calibur/tools/web_fetch.ex`
- Create: `lib/ex_calibur/tools/web_search.ex`
- Modify: `lib/ex_calibur/tools/registry.ex`
- Test: `test/ex_calibur/tools/web_tools_test.exs`

web_fetch: Req.get(url) then pipe HTML through `System.cmd("w3m", ["-dump", "-T", "text/html"], input: html)`. Fall back to raw body. Replaces fetch_url (keep alias).
web_search: `System.cmd("ddgr", ["--json", "--num", to_string(num), query])`, parse JSON results.

Both @safe. Move fetch_url out of @yolo.

**Commit:** `git commit -m "feat: add web_fetch (w3m extraction) and web_search (ddgr)"`

---

### Task 7: Media tools (4 tools)

**Files:**
- Create: `lib/ex_calibur/media.ex`
- Create: `lib/ex_calibur/tools/download_media.ex`
- Create: `lib/ex_calibur/tools/extract_audio.ex`
- Create: `lib/ex_calibur/tools/extract_frames.ex`
- Create: `lib/ex_calibur/tools/transcribe_audio.ex`
- Modify: `lib/ex_calibur/tools/registry.ex`
- Test: `test/ex_calibur/tools/media_tools_test.exs`

ExCalibur.Media shared helper:
```elixir
def media_dir, do: ExCalibur.Settings.get(:media_dir) || "/tmp/ex_calibur/media"
def job_dir do
  dir = Path.join(media_dir(), Ecto.UUID.generate())
  File.mkdir_p!(dir)
  dir
end
def cleanup(dir), do: File.rm_rf(dir)
```

download_media (write): `System.cmd("yt-dlp", ["-o", "#{dir}/%(title)s.%(ext)s", url])`
extract_audio (write): `System.cmd("ffmpeg", ["-i", input, "-vn", "-acodec", "pcm_s16le", output, "-y"])`
extract_frames (write): keyframes mode `["-vf", "select=eq(ptype\\,I)", ...]` or interval mode `["-vf", "fps=1/#{n}", ...]`
transcribe_audio (safe): Stub returning `{:error, :not_configured}` with TODO for whisper.

**Commit:** `git commit -m "feat: add media tools (download, extract audio/frames, transcribe stub)"`

---

### Task 8: Vision tools (3 tools)

**Files:**
- Create: `lib/ex_calibur/vision.ex`
- Create: `lib/ex_calibur/tools/describe_image.ex`
- Create: `lib/ex_calibur/tools/read_image_text.ex`
- Create: `lib/ex_calibur/tools/analyze_video.ex`
- Modify: `lib/ex_calibur/tools/registry.ex`
- Test: `test/ex_calibur/tools/vision_tools_test.exs`

ExCalibur.Vision routing:
```elixir
def describe(image_path, prompt \\ "Describe this image in detail.") do
  image_b64 = image_path |> File.read!() |> Base.encode64()
  case Settings.get(:vision_provider) || "ollama" do
    "ollama" -> ollama_vision(image_b64, prompt)
    "claude" -> claude_vision(image_b64, prompt)
  end
end
```

analyze_video: Orchestrates extract_frames → describe_image per frame → optional transcribe → combine into timeline text.

All @safe.

**Commit:** `git commit -m "feat: add vision tools (describe, OCR, video analysis)"`

---

### Task 9: Reclassify existing tools

**Files:**
- Modify: `lib/ex_calibur/tools/registry.ex`

Move fetch_url to @safe (or remove if replaced by web_fetch). Move run_quest to @dangerous. This should already be done if Tasks 0+6 are complete — verify and clean up.

**Commit:** `git commit -m "refactor: reclassify fetch_url→safe, run_quest→dangerous"`

---

### Task 10: Obsidian sync layer

**Files:**
- Create: `lib/ex_calibur/obsidian/sync.ex`
- Modify: `lib/ex_calibur/lore.ex`
- Modify: `lib/ex_calibur/lodge.ex`
- Test: `test/ex_calibur/obsidian/sync_test.exs`

See design doc Section 3 for full spec. Key functions:
- `sync_lore_entry/1`: Writes `ExCalibur/Lore/slug.md` with YAML frontmatter
- `sync_lodge_card/1`: Writes `ExCalibur/Lodge/slug.md` with YAML frontmatter
- `slug/1`: Slugify title + date
- `vault_path/0`: From Settings, construct full path to vault
- `sync_enabled?/0`: Check Settings.get(:obsidian_sync_enabled)

Wire in via `Task.start(fn -> Sync.sync_lore_entry(entry) end)` — fire-and-forget, don't block the main flow.

**Commit:** `git commit -m "feat: Obsidian sync layer for lore entries and lodge cards"`

---

### Task 11: Wire guild charters to new tools

**Files:** All 19 charter files in `lib/ex_calibur/charters/`

See design doc Section 5 for complete per-guild wiring table. Two changes per charter:
1. `resource_definitions/0`: Change `"tools" => "all_safe"` to the appropriate tier or specific tool list
2. `quest_definitions/0`: Expand `loop_tools` arrays on quests that use reflect mode

For Everyday Council specifically: per-member tool config (journal-keeper gets "write", others get "all_safe" or specific lists).

**Commit:** `git commit -m "feat: wire all 19 guild charters to new tool tiers and loop_tools"`

---

### Task 12: New source types (Obsidian, Email, Media)

**Files:**
- Create: `lib/ex_calibur/sources/obsidian_watcher.ex`
- Create: `lib/ex_calibur/sources/email_source.ex`
- Create: `lib/ex_calibur/sources/media_source.ex`
- Modify: `lib/ex_calibur/sources/source_worker.ex`
- Modify: `lib/ex_calibur/sources/book.ex`
- Tests for each

See design doc Section 6 for specs. Each implements `init/1` and `fetch/2` callbacks.

**Commit:** `git commit -m "feat: add Obsidian, Email, and Media source types"`

---

### Task 13: Settings UI page

**Files:**
- Create: `lib/ex_calibur_web/live/settings_live.ex`
- Modify: `lib/ex_calibur_web/router.ex`
- Modify: `lib/ex_calibur_web/components/layouts/app.html.heex`
- Test: `test/ex_calibur_web/live/settings_live_test.exs`

7 form sections, each with phx-submit saving to Settings.put/2. See design doc Section 7.

**Commit:** `git commit -m "feat: add /settings page for tool configuration"`

---

### Task 14: Integration test

**Files:**
- Test: `test/ex_calibur/integration/everyday_council_flow_test.exs`

End-to-end smoke test of the full pipeline with new tools.

**Commit:** `git commit -m "test: add integration test for Everyday Council with new tools"`
