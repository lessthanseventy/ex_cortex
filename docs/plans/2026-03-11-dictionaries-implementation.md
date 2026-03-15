# Dictionaries: Query Tool & Seed Data Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add a `query_dictionary` tool that lets agents search named reference dictionaries, and seed five pre-baked CSV reference datasets (sports teams, stock tickers, WCAG criteria, regulatory frameworks, currency codes).

**Architecture:** The Dictionary schema, CRUD, UI, and context provider already exist. This plan adds `Library.get_dictionary_by_name/1`, a new `QueryDictionary` tool module following the same pattern as `QueryLore`, registers it in the tool registry as `:safe`, writes five CSV seed files in `priv/dictionaries/`, and wires them into `seeds.exs` idempotently.

**Tech Stack:** Elixir, Phoenix, Ecto/Postgres, ExUnit with DataCase, `ReqLLM.Tool`

---

### Task 1: Add `get_dictionary_by_name/1` to Library

**Files:**
- Modify: `lib/ex_cortex/library.ex`
- Create: `test/ex_cortex/library_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_cortex/library_test.exs
defmodule ExCortex.LibraryTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Library

  test "get_dictionary_by_name returns dictionary when found" do
    {:ok, _} = Library.create_dictionary(%{name: "test_dict", content: "hello"})
    dict = Library.get_dictionary_by_name("test_dict")
    assert dict.name == "test_dict"
  end

  test "get_dictionary_by_name returns nil when not found" do
    assert Library.get_dictionary_by_name("nope") == nil
  end
end
```

**Step 2: Run test to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/library_test.exs' --pane=main:1.3
```

Expected: FAIL — `get_dictionary_by_name/1` undefined.

**Step 3: Add the function to `lib/ex_cortex/library.ex`**

Add after line 10 (`get_dictionary/1`):

```elixir
def get_dictionary_by_name(name), do: Repo.get_by(Dictionary, name: name)
```

**Step 4: Run test to verify it passes**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/library_test.exs' --pane=main:1.3
```

Expected: 2 tests pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex/library.ex test/ex_cortex/library_test.exs
git commit -m "feat: add get_dictionary_by_name/1 to Library"
```

---

### Task 2: Implement `QueryDictionary` tool

**Files:**
- Create: `lib/ex_cortex/tools/query_dictionary.ex`
- Create: `test/ex_cortex/tools/query_dictionary_test.exs`

**Step 1: Write the failing tests**

```elixir
# test/ex_cortex/tools/query_dictionary_test.exs
defmodule ExCortex.Tools.QueryDictionaryTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Library
  alias ExCortex.Tools.QueryDictionary

  setup do
    {:ok, _} =
      Library.create_dictionary(%{
        name: "sports_teams",
        content:
          "team,abbreviation,league\nKansas City Chiefs,KC,NFL\nGreen Bay Packers,GB,NFL\nLos Angeles Lakers,LAL,NBA",
        content_type: "csv"
      })

    {:ok, _} =
      Library.create_dictionary(%{
        name: "glossary",
        content: "Lore: accumulated knowledge\nQuest: a pipeline run\nMember: a role in a guild",
        content_type: "text"
      })

    :ok
  end

  test "returns matching CSV rows with header" do
    {:ok, result} = QueryDictionary.call(%{"dictionary" => "sports_teams", "query" => "kansas"})
    assert result =~ "Kansas City Chiefs"
    assert result =~ "team,abbreviation,league"
    refute result =~ "Green Bay Packers"
  end

  test "is case-insensitive" do
    {:ok, result} = QueryDictionary.call(%{"dictionary" => "sports_teams", "query" => "KANSAS"})
    assert result =~ "Kansas City Chiefs"
  end

  test "returns matching text lines" do
    {:ok, result} = QueryDictionary.call(%{"dictionary" => "glossary", "query" => "quest"})
    assert result =~ "Quest: a pipeline run"
    refute result =~ "Lore:"
  end

  test "returns error when dictionary not found" do
    {:error, msg} = QueryDictionary.call(%{"dictionary" => "nonexistent", "query" => "foo"})
    assert msg =~ "not found"
  end

  test "returns no-match message when query has no hits" do
    {:ok, result} =
      QueryDictionary.call(%{"dictionary" => "sports_teams", "query" => "zzz_no_match"})

    assert result =~ "No matches"
  end

  test "req_llm_tool/0 returns a valid ReqLLM.Tool struct" do
    tool = QueryDictionary.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "query_dictionary"
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/tools/query_dictionary_test.exs' --pane=main:1.3
```

Expected: FAIL — `QueryDictionary` undefined.

**Step 3: Implement the tool**

```elixir
# lib/ex_cortex/tools/query_dictionary.ex
defmodule ExCortex.Tools.QueryDictionary do
  @moduledoc "Tool: search a named dictionary for matching rows or lines."

  alias ExCortex.Library

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "query_dictionary",
      description:
        "Search a reference dictionary by name. Returns matching rows (CSV) or lines (text/markdown) that contain the query string.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "dictionary" => %{
            "type" => "string",
            "description" => "Exact name of the dictionary to search"
          },
          "query" => %{
            "type" => "string",
            "description" => "Search term (case-insensitive)"
          }
        },
        "required" => ["dictionary", "query"]
      },
      callback: &call/1
    )
  end

  def call(%{"dictionary" => name, "query" => query}) do
    case Library.get_dictionary_by_name(name) do
      nil -> {:error, "Dictionary '#{name}' not found"}
      dict -> {:ok, search(dict, query)}
    end
  end

  defp search(%{content_type: "csv", name: name, content: content}, query) do
    q = String.downcase(query)
    [header | rows] = String.split(content, "\n", trim: true)
    matches = Enum.filter(rows, fn row -> String.contains?(String.downcase(row), q) end)

    if matches == [] do
      "No matches found in \"#{name}\"."
    else
      "Found #{length(matches)} match(es) in \"#{name}\":\n\n#{header}\n#{Enum.join(matches, "\n")}"
    end
  end

  defp search(%{name: name, content: content}, query) do
    q = String.downcase(query)

    matches =
      content
      |> String.split("\n", trim: true)
      |> Enum.filter(fn line -> String.contains?(String.downcase(line), q) end)

    if matches == [] do
      "No matches found in \"#{name}\"."
    else
      "Found #{length(matches)} match(es) in \"#{name}\":\n\n#{Enum.join(matches, "\n")}"
    end
  end
end
```

**Step 4: Run tests to verify they pass**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/tools/query_dictionary_test.exs' --pane=main:1.3
```

Expected: 6 tests pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex/tools/query_dictionary.ex test/ex_cortex/tools/query_dictionary_test.exs
git commit -m "feat: add QueryDictionary tool"
```

---

### Task 3: Register `QueryDictionary` in the tool registry

**Files:**
- Modify: `lib/ex_cortex/tools/registry.ex`
- Modify: `test/ex_cortex/tools/registry_test.exs`

**Step 1: Update the registry test — add assertion that `query_dictionary` is in safe tools**

Add to `test/ex_cortex/tools/registry_test.exs` inside the first test:

```elixir
assert "query_dictionary" in names
```

The full updated first test:

```elixir
test "resolve_tools(:all_safe) returns only safe tools" do
  tools = Registry.resolve_tools(:all_safe)
  assert Enum.all?(tools, &is_struct(&1, ReqLLM.Tool))
  names = Enum.map(tools, & &1.name)
  assert "query_lore" in names
  assert "query_dictionary" in names
  refute "run_quest" in names
end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/tools/registry_test.exs' --pane=main:1.3
```

Expected: FAIL — `query_dictionary` not in safe tools.

**Step 3: Update the registry**

In `lib/ex_cortex/tools/registry.ex`, change:

```elixir
alias ExCortex.Tools.{QueryLore, FetchUrl, RunQuest}

@safe [QueryLore, FetchUrl]
```

To:

```elixir
alias ExCortex.Tools.{QueryDictionary, QueryLore, FetchUrl, RunQuest}

@safe [QueryDictionary, QueryLore, FetchUrl]
```

**Step 4: Run tests to verify they pass**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/tools/registry_test.exs' --pane=main:1.3
```

Expected: all tests pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex/tools/registry.ex test/ex_cortex/tools/registry_test.exs
git commit -m "feat: register QueryDictionary as safe tool"
```

---

### Task 4: Write the five seed CSV files

**Files:**
- Create: `priv/dictionaries/sports_teams.csv`
- Create: `priv/dictionaries/stock_tickers.csv`
- Create: `priv/dictionaries/wcag_criteria.csv`
- Create: `priv/dictionaries/regulatory_frameworks.csv`
- Create: `priv/dictionaries/currency_codes.csv`

No tests — these are data files. Just generate them from training knowledge. No web scraping needed.

**Step 1: Create `priv/dictionaries/` directory and write the files**

**`sports_teams.csv`** — schema: `team,abbreviation,league,conference_or_division,city`
Cover NFL (32), NBA (30), MLB (30), NHL (32), MLS (~30). ~154 rows total.

**`stock_tickers.csv`** — schema: `company,ticker,sector,index`
S&P 500 companies. ~500 rows.

**`wcag_criteria.csv`** — schema: `criterion_id,level,title,description`
All WCAG 2.1 success criteria (A, AA, AAA). ~78 rows.

**`regulatory_frameworks.csv`** — schema: `name,abbreviation,jurisdiction,domain,description`
GDPR, HIPAA, CCPA, SOC2, PCI-DSS, ISO 27001, FERPA, COPPA, FTC Act, FINRA, Basel III, AML/KYC, NIST CSF, CAN-SPAM, TCPA, GLBA, PIPEDA, Australia Privacy Act, PDPA (Singapore), LGPD (Brazil). ~20 rows.

**`currency_codes.csv`** — schema: `code,name,symbol,example_countries`
All active ISO 4217 currency codes. ~180 rows.

**Step 2: Verify files exist and are well-formed**

```bash
tmux-cli send 'head -3 /home/andrew/projects/ex_cortex/priv/dictionaries/sports_teams.csv && echo "---" && wc -l /home/andrew/projects/ex_cortex/priv/dictionaries/*.csv' --pane=main:1.3
```

Expected: each file shows a valid header + first row.

**Step 3: Commit**

```bash
git add priv/dictionaries/
git commit -m "feat: add pre-baked reference dictionary CSV files"
```

---

### Task 5: Wire seed files into `seeds.exs`

**Files:**
- Modify: `priv/repo/seeds.exs`

**Step 1: Add seeding logic to `priv/repo/seeds.exs`**

```elixir
# Seed pre-baked dictionaries from priv/dictionaries/*.csv
descriptions = %{
  "sports_teams" => "Sports teams across NFL, NBA, MLB, NHL, and MLS with abbreviations and divisions.",
  "stock_tickers" => "S&P 500 company names, ticker symbols, and sectors.",
  "wcag_criteria" => "WCAG 2.1 success criteria with level (A/AA/AAA) and descriptions.",
  "regulatory_frameworks" => "Major regulatory frameworks and compliance standards by jurisdiction and domain.",
  "currency_codes" => "ISO 4217 currency codes with names, symbols, and example countries."
}

for path <- Path.wildcard("priv/dictionaries/*.csv") do
  name = Path.basename(path, ".csv")

  unless ExCortex.Library.get_dictionary_by_name(name) do
    content = File.read!(path)

    {:ok, _} =
      ExCortex.Library.create_dictionary(%{
        name: name,
        content: content,
        content_type: "csv",
        description: Map.get(descriptions, name, "Pre-baked reference dataset.")
      })

    IO.puts("Seeded dictionary: #{name}")
  end
end
```

**Step 2: Run seeds and verify output**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix run priv/repo/seeds.exs' --pane=main:1.3
```

Expected: prints "Seeded dictionary: sports_teams" etc. for each file.

**Step 3: Run seeds again to verify idempotency**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix run priv/repo/seeds.exs' --pane=main:1.3
```

Expected: no output (already seeded, skipped).

**Step 4: Commit**

```bash
git add priv/repo/seeds.exs
git commit -m "feat: seed pre-baked dictionaries on mix run seeds.exs"
```

---

### Task 6: Full test suite pass

**Step 1: Run all tests**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test' --pane=main:1.3
```

Expected: all tests pass, no warnings.

**Step 2: Format**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix format' --pane=main:1.3
```

**Step 3: Commit any format fixes if needed**

```bash
git add -A && git commit -m "style: mix format"
```
