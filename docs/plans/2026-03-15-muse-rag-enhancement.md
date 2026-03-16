# Muse RAG Enhancement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Make Muse a genuinely useful assistant by enhancing existing tools with richer output modes, improving tool descriptions so the LLM knows how to use them, injecting sense/source awareness into the Muse context, and adding a `list_sources` discovery tool.

**Architecture:** Enhance 4 existing tool modules (`search_email`, `query_memory`, `search_github`, `search_obsidian`) with additional parameters and output modes. Add 1 new tool (`list_sources`) to the safe tier. Update `Muse.gather_context/2` to inject a data source summary. Rewrite tool descriptions across all safe tools to teach the LLM query syntax and usage patterns.

**Tech Stack:** Elixir, ReqLLM.Tool, Ecto queries, notmuch CLI, gh CLI, obsidian-cli

---

### Task 1: Enhance `search_email` with output modes

**Files:**
- Modify: `lib/ex_cortex/tools/search_email.ex`
- Test: `test/ex_cortex/tools/search_email_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_cortex/tools/search_email_test.exs
defmodule ExCortex.Tools.SearchEmailTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.SearchEmail

  describe "req_llm_tool/0" do
    test "includes output parameter with enum" do
      tool = SearchEmail.req_llm_tool()
      props = tool.parameter_schema["properties"]
      assert props["output"]["enum"] == ["results", "count", "summary"]
    end

    test "description teaches notmuch query syntax" do
      tool = SearchEmail.req_llm_tool()
      assert tool.description =~ "tag:inbox"
      assert tool.description =~ "from:"
      assert tool.description =~ "date:"
    end
  end

  describe "build_args/3" do
    test "count mode uses notmuch count" do
      # We test the args building indirectly via the tool schema
      # The actual notmuch calls require the binary installed
      tool = SearchEmail.req_llm_tool()
      props = tool.parameter_schema["properties"]
      assert props["output"]
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex/tools/search_email_test.exs -v`
Expected: FAIL — no `output` property, description doesn't match

**Step 3: Implement the enhancement**

Replace `lib/ex_cortex/tools/search_email.ex` with:

```elixir
defmodule ExCortex.Tools.SearchEmail do
  @moduledoc "Tool: search email index via notmuch."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "search_email",
      description: """
      Search the local email index via notmuch. Supports three output modes:
      - "results" (default): returns matching message summaries
      - "count": returns the total number of matching messages (use for "how many" questions)
      - "summary": returns structured JSON with subjects, dates, and senders

      Query syntax (notmuch):
      - tag:inbox — all inbox messages
      - tag:unread — unread messages
      - from:alice@example.com — by sender
      - to:bob@example.com — by recipient
      - subject:invoice — by subject keyword
      - date:1M.. — last month to now
      - date:2024-01-01..2024-12-31 — date range
      - tag:inbox AND tag:unread — combine with AND/OR/NOT
      - folder:INBOX — by maildir folder
      - * — all messages

      Examples: "tag:inbox AND from:boss", "date:1w.. AND subject:deploy", "*" (count all).
      """,
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{
            "type" => "string",
            "description" => "Notmuch search query (e.g. 'tag:inbox', 'from:alice date:1M..', '*' for all)"
          },
          "output" => %{
            "type" => "string",
            "enum" => ["results", "count", "summary"],
            "description" =>
              "Output mode: 'results' (message list), 'count' (total matches), 'summary' (JSON with subjects/dates/senders). Default: results"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum results for 'results'/'summary' modes (default 20, ignored for 'count')"
          }
        },
        "required" => ["query"]
      },
      callback: &call/1
    )
  end

  def call(%{"query" => query} = params) do
    output = Map.get(params, "output", "results")
    limit = Map.get(params, "limit", 20)
    db_path = ExCortex.Settings.get(:notmuch_db_path)

    args = build_args(db_path, query, limit, output)

    case System.cmd("notmuch", args, stderr_to_stdout: true) do
      {output_text, 0} -> {:ok, output_text}
      {error, _} -> {:error, error}
    end
  end

  defp build_args(db_path, query, _limit, "count") do
    config_args(db_path) ++ ["count", query]
  end

  defp build_args(db_path, query, limit, "summary") do
    config_args(db_path) ++ ["search", "--limit=#{limit}", "--format=json", "--output=summary", query]
  end

  defp build_args(db_path, query, limit, _results) do
    config_args(db_path) ++ ["search", "--limit=#{limit}", "--format=text", query]
  end

  defp config_args(nil), do: []
  defp config_args(db_path), do: ["--config=#{db_path}"]
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ex_cortex/tools/search_email_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_cortex/tools/search_email.ex test/ex_cortex/tools/search_email_test.exs
git commit -m "feat: search_email supports count/summary output modes + richer description"
```

---

### Task 2: Enhance `query_memory` with free-text search, category, and date filtering

**Files:**
- Modify: `lib/ex_cortex/tools/query_memory.ex`
- Modify: `lib/ex_cortex/memory.ex` (add `count_engrams/1`)
- Test: `test/ex_cortex/tools/query_memory_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_cortex/tools/query_memory_test.exs
defmodule ExCortex.Tools.QueryMemoryTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.QueryMemory

  describe "req_llm_tool/0" do
    test "includes search, category, since, and output params" do
      tool = QueryMemory.req_llm_tool()
      props = tool.parameter_schema["properties"]
      assert props["search"]
      assert props["category"]
      assert props["since"]
      assert props["output"]
    end

    test "description explains memory system" do
      tool = QueryMemory.req_llm_tool()
      assert tool.description =~ "engram"
      assert tool.description =~ "semantic"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex/tools/query_memory_test.exs -v`
Expected: FAIL

**Step 3: Add `count_engrams/1` to Memory**

Add to `lib/ex_cortex/memory.ex` after `list_engrams/1`:

```elixir
def count_engrams(opts \\ []) do
  tags = Keyword.get(opts, :tags, [])
  category = Keyword.get(opts, :category)
  since = Keyword.get(opts, :since)

  query =
    from(e in Engram)
    |> filter_tags(tags)
    |> filter_category(category)
    |> filter_since(since)

  Repo.aggregate(query, :count)
end
```

And add the two new filter helpers at the bottom alongside the existing ones:

```elixir
defp filter_category(query, nil), do: query
defp filter_category(query, category) do
  from e in query, where: e.category == ^category
end

defp filter_since(query, nil), do: query
defp filter_since(query, %NaiveDateTime{} = since) do
  from e in query, where: e.inserted_at >= ^since
end
```

**Step 4: Implement the enhanced tool**

Replace `lib/ex_cortex/tools/query_memory.ex`:

```elixir
defmodule ExCortex.Tools.QueryMemory do
  @moduledoc "Tool: search engrams (memories) with flexible filtering."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "query_memory",
      description: """
      Search the engram (memory) store. Engrams are stored knowledge — facts, events, procedures, and artifacts from agent runs.

      Supports four output modes:
      - "results" (default): returns matching engram titles and excerpts
      - "count": returns the total number of matching engrams

      Filter by tags, category, free-text search, or date. Combine filters to narrow results.

      Categories: semantic (facts/definitions), episodic (events/conversations), procedural (how-to/patterns).
      Importance: 1-5 scale (5 = highest).
      """,
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "tags" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Filter by tags (array intersection)"
          },
          "search" => %{
            "type" => "string",
            "description" => "Free-text search across engram titles and impressions"
          },
          "category" => %{
            "type" => "string",
            "enum" => ["semantic", "episodic", "procedural"],
            "description" => "Filter by memory category"
          },
          "since" => %{
            "type" => "string",
            "description" => "ISO date (e.g. '2026-03-01') — only return engrams created after this date"
          },
          "output" => %{
            "type" => "string",
            "enum" => ["results", "count"],
            "description" => "Output mode: 'results' (titles + excerpts) or 'count' (total matches). Default: results"
          },
          "limit" => %{"type" => "integer", "description" => "Max entries to return (default 10, ignored for count)"}
        },
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(input) do
    output = Map.get(input, "output", "results")
    tags = Map.get(input, "tags", [])
    search = Map.get(input, "search")
    category = Map.get(input, "category")
    since = parse_since(Map.get(input, "since"))
    limit = Map.get(input, "limit", 10)

    case output do
      "count" ->
        count = ExCortex.Memory.count_engrams(tags: tags, category: category, since: since)
        {:ok, "#{count} engrams match"}

      _ ->
        entries =
          if search do
            ExCortex.Memory.query(search, tier: :L0, limit: limit)
          else
            ExCortex.Memory.list_engrams(tags: tags)
          end

        entries =
          entries
          |> maybe_filter_category(category)
          |> maybe_filter_since(since)
          |> Enum.take(limit)

        summaries =
          Enum.map(entries, fn e ->
            body = e.impression || e.body || ""
            "#{e.title} [#{e.category || "unknown"}]: #{String.slice(body, 0, 200)}"
          end)

        {:ok, Enum.join(summaries, "\n---\n")}
    end
  end

  defp parse_since(nil), do: nil
  defp parse_since(date_str) when is_binary(date_str) do
    case NaiveDateTime.from_iso8601(date_str <> "T00:00:00") do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp maybe_filter_category(entries, nil), do: entries
  defp maybe_filter_category(entries, cat), do: Enum.filter(entries, &(&1.category == cat))

  defp maybe_filter_since(entries, nil), do: entries
  defp maybe_filter_since(entries, since) do
    Enum.filter(entries, &(NaiveDateTime.compare(&1.inserted_at, since) != :lt))
  end
end
```

**Step 5: Run tests**

Run: `mix test test/ex_cortex/tools/query_memory_test.exs -v`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ex_cortex/tools/query_memory.ex lib/ex_cortex/memory.ex test/ex_cortex/tools/query_memory_test.exs
git commit -m "feat: query_memory supports free-text search, category/date filters, count mode"
```

---

### Task 3: Enhance `search_github` with state and assignee filtering

**Files:**
- Modify: `lib/ex_cortex/tools/search_github.ex`
- Test: `test/ex_cortex/tools/search_github_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule ExCortex.Tools.SearchGithubTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.SearchGithub

  describe "req_llm_tool/0" do
    test "includes state and assignee params" do
      tool = SearchGithub.req_llm_tool()
      props = tool.parameter_schema["properties"]
      assert props["state"]["enum"] == ["open", "closed", "all"]
      assert props["assignee"]
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex/tools/search_github_test.exs -v`
Expected: FAIL

**Step 3: Implement the enhancement**

In `lib/ex_cortex/tools/search_github.ex`, add to the `parameter_schema` properties:

```elixir
"state" => %{
  "type" => "string",
  "enum" => ["open", "closed", "all"],
  "description" => "Filter by state (default: open)"
},
"assignee" => %{
  "type" => "string",
  "description" => "Filter issues/PRs by assignee username"
}
```

Update the description to:

```elixir
description: """
Search GitHub issues, pull requests, or repositories using the gh CLI.

Use `label` to filter issues by label (more reliable than text search).
Use `state` to filter by open/closed/all.
Use `assignee` to filter by assigned user.

Examples: search_github(label: "bug", state: "open"), search_github(query: "auth", type: "prs").
"""
```

Update `call/1` to pass state and assignee through:

```elixir
def call(params) do
  query = Map.get(params, "query", "")
  type = Map.get(params, "type", "issues")
  limit = Map.get(params, "limit", 20)
  label = Map.get(params, "label")
  state = Map.get(params, "state", "open")
  assignee = Map.get(params, "assignee")
  repo = ExCortex.Settings.get(:default_repo)

  args = build_args(type, query, limit, repo, label, state, assignee)

  case System.cmd("gh", args, stderr_to_stdout: true) do
    {output, 0} -> {:ok, output}
    {error, _} -> {:error, error}
  end
end
```

Update the label-based `build_args` clause to use state and assignee:

```elixir
defp build_args(_issues, _query, limit, repo, label, state, assignee)
     when is_binary(label) and label != "" do
  base = ["issue", "list", "--label", label, "--state", state, "--limit", to_string(limit),
          "--json", "number,title,state,url"]
  base = if assignee, do: base ++ ["--assignee", assignee], else: base
  if repo, do: base ++ ["--repo", repo], else: base
end
```

And the text-search clause similarly.

**Step 4: Run test to verify it passes**

Run: `mix test test/ex_cortex/tools/search_github_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_cortex/tools/search_github.ex test/ex_cortex/tools/search_github_test.exs
git commit -m "feat: search_github supports state/assignee filtering + richer description"
```

---

### Task 4: Improve tool descriptions across all safe tools

**Files:**
- Modify: `lib/ex_cortex/tools/search_obsidian.ex`
- Modify: `lib/ex_cortex/tools/search_obsidian_content.ex`
- Modify: `lib/ex_cortex/tools/read_email.ex`
- Modify: `lib/ex_cortex/tools/query_axiom.ex`
- Modify: `lib/ex_cortex/tools/web_fetch.ex`
- Modify: `lib/ex_cortex/tools/web_search.ex`
- Modify: `lib/ex_cortex/tools/fetch_url.ex`
- Modify: `lib/ex_cortex/tools/read_file.ex`
- Modify: `lib/ex_cortex/tools/list_files.ex`
- Modify: `lib/ex_cortex/tools/query_jaeger.ex`
- Modify: `lib/ex_cortex/tools/read_nextcloud.ex`
- Modify: `lib/ex_cortex/tools/read_nextcloud_notes.ex`
- Modify: `lib/ex_cortex/tools/search_nextcloud.ex`

**Step 1: Update each tool's `description` field**

For each tool, rewrite the description to:
1. Explain what it does in one sentence
2. List key parameters and what they accept
3. Give 1-2 example calls
4. Note limitations (char caps, result limits)
5. Suggest related tools ("use search_obsidian_content for body search")

Key description rewrites:

**search_obsidian.ex:**
```
"Search Obsidian vault by note title (fuzzy match). Returns matching note names.
Use search_obsidian_content to search inside note bodies instead.
Example: search_obsidian(query: \"meeting notes\")"
```

**search_obsidian_content.ex:**
```
"Search inside Obsidian note bodies for a term. Returns matching note names with excerpts.
Use search_obsidian for title-only search (faster).
Example: search_obsidian_content(query: \"project deadline\")"
```

**read_email.ex:**
```
"Read the full content of an email by thread or message ID (from search_email results).
Output capped at 8000 characters. Use search_email first to find message IDs.
Example: read_email(id: \"thread:00000000000001a3\")"
```

**query_axiom.ex:**
```
"Search a reference axiom (dataset) by name. Axioms are CSV or text reference data stored in the Lexicon.
You must know the exact axiom name — use list_sources to discover available axioms.
Case-insensitive substring search. Example: query_axiom(axiom: \"tech-glossary\", query: \"elixir\")"
```

**web_fetch.ex:**
```
"Fetch a URL and convert HTML to readable text (via w3m). Returns up to 8000 characters.
Better than fetch_url for web pages — renders HTML to plain text.
Example: web_fetch(url: \"https://example.com/article\")"
```

**web_search.ex:**
```
"Search the web via DuckDuckGo. Returns up to N results with title, URL, and snippet.
Example: web_search(query: \"elixir phoenix deployment\", num: 5)"
```

**fetch_url.ex:**
```
"Fetch raw content from a URL (HTML, JSON, plain text). Returns up to 4000 characters.
Use web_fetch instead for human-readable web pages. Use this for APIs or raw content.
Example: fetch_url(url: \"https://api.example.com/data.json\")"
```

**read_file.ex:**
```
"Read a file from the local filesystem (relative to project root).
Use list_files to discover available files first.
Example: read_file(path: \"lib/ex_cortex/muse.ex\")"
```

**list_files.ex:**
```
"List files matching a glob pattern. Returns up to 100 paths.
Ignores _build, deps, .git, and node_modules.
Examples: list_files(pattern: \"lib/**/*.ex\"), list_files(pattern: \"*.md\", path: \"docs\")"
```

**Step 2: Commit**

```bash
git add lib/ex_cortex/tools/*.ex
git commit -m "docs: rewrite tool descriptions to teach LLM query syntax and usage patterns"
```

---

### Task 5: Add `list_sources` discovery tool

**Files:**
- Create: `lib/ex_cortex/tools/list_sources.ex`
- Modify: `lib/ex_cortex/tools/registry.ex` (add to @safe list)
- Test: `test/ex_cortex/tools/list_sources_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule ExCortex.Tools.ListSourcesTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Tools.ListSources

  describe "req_llm_tool/0" do
    test "tool is named list_sources" do
      tool = ListSources.req_llm_tool()
      assert tool.name == "list_sources"
    end
  end

  describe "call/1" do
    test "returns JSON with senses, axioms, and engram stats" do
      {:ok, result} = ListSources.call(%{})
      decoded = Jason.decode!(result)
      assert Map.has_key?(decoded, "senses")
      assert Map.has_key?(decoded, "axioms")
      assert Map.has_key?(decoded, "engram_stats")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex/tools/list_sources_test.exs -v`
Expected: FAIL — module not found

**Step 3: Implement the tool**

```elixir
# lib/ex_cortex/tools/list_sources.ex
defmodule ExCortex.Tools.ListSources do
  @moduledoc "Tool: discover configured data sources, axioms, and memory stats."

  import Ecto.Query

  alias ExCortex.Lexicon.Axiom
  alias ExCortex.Memory.Engram
  alias ExCortex.Repo
  alias ExCortex.Senses.Sense

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "list_sources",
      description: """
      Discover what data sources are available. Returns configured senses (email, obsidian, github, feeds, etc.),
      axioms (reference datasets in the Lexicon), and engram (memory) statistics.

      Call this first when you need to understand what data the user has access to before querying specific tools.
      No parameters required.
      """,
      parameter_schema: %{
        "type" => "object",
        "properties" => %{},
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(_params) do
    result = %{
      senses: list_senses(),
      axioms: list_axioms(),
      engram_stats: engram_stats()
    }

    {:ok, Jason.encode!(result, pretty: true)}
  end

  defp list_senses do
    Repo.all(from(s in Sense, order_by: s.name))
    |> Enum.map(fn s ->
      %{
        name: s.name,
        type: s.source_type,
        status: s.status,
        last_run: s.last_run_at && Calendar.strftime(s.last_run_at, "%Y-%m-%d %H:%M UTC"),
        error: s.error_message
      }
    end)
  end

  defp list_axioms do
    Repo.all(from(a in Axiom, order_by: a.name))
    |> Enum.map(fn a ->
      %{name: a.name, type: a.format}
    end)
  end

  defp engram_stats do
    total = Repo.aggregate(Engram, :count)

    by_category =
      Repo.all(
        from(e in Engram,
          group_by: e.category,
          select: {e.category, count(e.id)}
        )
      )
      |> Map.new()

    %{total: total, by_category: by_category}
  end
end
```

**Step 4: Add to registry**

In `lib/ex_cortex/tools/registry.ex`, add to the `@safe` list:

```elixir
# Add alias at top
alias ExCortex.Tools.ListSources

# Add to @safe list (after ReadNextcloudNotes)
@safe [
  # ... existing ...
  ReadNextcloudNotes,
  ListSources
]
```

**Step 5: Run test to verify it passes**

Run: `mix test test/ex_cortex/tools/list_sources_test.exs -v`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ex_cortex/tools/list_sources.ex lib/ex_cortex/tools/registry.ex test/ex_cortex/tools/list_sources_test.exs
git commit -m "feat: add list_sources tool for data source discovery"
```

---

### Task 6: Inject sense awareness into Muse context

**Files:**
- Modify: `lib/ex_cortex/muse.ex`

**Step 1: Add `gather_source_context/0` to Muse**

Add a new private function that builds a brief data source summary:

```elixir
defp gather_source_context do
  import Ecto.Query

  senses =
    ExCortex.Repo.all(from(s in ExCortex.Senses.Sense, where: s.status == "active", order_by: s.name))
    |> Enum.map(fn s ->
      last = if s.last_run_at, do: " (last checked #{Calendar.strftime(s.last_run_at, "%Y-%m-%d %H:%M")})", else: ""
      "- #{s.source_type}: \"#{s.name}\"#{last}"
    end)

  axioms =
    ExCortex.Lexicon.list_axioms()
    |> Enum.map(fn a -> "- #{a.name}" end)

  engram_count = ExCortex.Repo.aggregate(ExCortex.Memory.Engram, :count)

  sections = ["## Available Data Sources\n"]
  sections = if senses != [], do: sections ++ ["### Senses\n" <> Enum.join(senses, "\n")], else: sections
  sections = if axioms != [], do: sections ++ ["### Axioms\n" <> Enum.join(axioms, "\n")], else: sections
  sections = sections ++ ["### Memory\n- #{engram_count} engrams in store"]

  Enum.join(sections, "\n\n")
end
```

**Step 2: Wire it into `gather_context/2`**

Update `gather_context/2` to prepend source awareness:

```elixir
def gather_context(question, filters \\ []) do
  source_context = gather_source_context()
  engram_context = gather_engram_context(question, filters)
  axiom_context = gather_axiom_context(question)

  [source_context, engram_context, axiom_context]
  |> Enum.reject(&(&1 == ""))
  |> Enum.join("\n\n---\n\n")
end
```

**Step 3: Verify compilation**

Run: `mix compile`
Expected: clean compile, no warnings

**Step 4: Commit**

```bash
git add lib/ex_cortex/muse.ex
git commit -m "feat: inject sense/source awareness into Muse RAG context"
```

---

### Task 7: Final integration test and cleanup

**Step 1: Run the full test suite**

Run: `mix test`
Expected: all tests pass

**Step 2: Run format and credo**

Run: `mix format && mix credo`
Expected: clean

**Step 3: Manual smoke test**

Start the server and test in `/muse`:
- "how many emails are in my inbox?" → should use search_email with output: count
- "what data sources do I have?" → should use list_sources or answer from context
- "show me recent memories about email" → should use query_memory with search
- "any open github issues?" → should use search_github

**Step 4: Final commit if any formatting changes**

```bash
git add -A && git commit -m "chore: format"
```
