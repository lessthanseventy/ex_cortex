# Dictionaries: Query Tool & Pre-baked Seed Data

## Overview

Dictionaries are a first-class Library citizen alongside Scrolls and Books. The
schema, CRUD, UI, file upload, and context provider already exist. This plan
adds a `query_dictionary` tool so agents can search dictionaries on demand,
plus five pre-baked seed datasets for common reference data.

## 1. What Already Exists

- `ExCalibur.Library.Dictionary` schema — name, description, content (text),
  content_type (text/markdown/csv/json), tags, filename
- `ExCalibur.Library` CRUD — list, get, create, update, delete
- `ExCalibur.ContextProviders.Dictionary` — injects full content into prompt
- Library UI — create, edit, delete, upload (tabs: scrolls/books/heralds/dictionaries)

## 2. New: `query_dictionary` Tool

**Tier:** safe
**Name:** `query_dictionary`
**Description:** Search a named reference dictionary. Returns matching rows or lines.

### Parameters

```json
{
  "dictionary": "sports_teams",
  "query": "kansas city"
}
```

### Query Logic

- **CSV**: parse rows, return all rows where any column contains the query
  string (case-insensitive). Include the header row in results.
- **text/markdown**: return lines containing the query string.
- **JSON**: return top-level keys/objects where stringified value contains query.

### Response Format

```
Found 2 matches in "sports_teams":

Team,Abbreviation,League,Division,City
Kansas City Chiefs,KC,NFL,AFC West,Kansas City
Kansas City Royals,KC,MLB,AL Central,Kansas City
```

Returns `{:error, "Dictionary '#{name}' not found"}` if no match.

### New Library Helper

```elixir
def get_dictionary_by_name(name) do
  Repo.get_by(Dictionary, name: name)
end
```

### Module Location

`lib/ex_calibur/tools/query_dictionary.ex` — follows the same pattern as
existing tools.

## 3. Pre-baked Seed Dictionaries

Five CSV files in `priv/dictionaries/`, seeded via `priv/repo/seeds.exs`.
Pre-baked dictionaries are treated identically to user-created ones (no special
system flag — YAGNI).

### Files

| File | Dictionary Name | Rows (approx) |
|------|----------------|---------------|
| `sports_teams.csv` | sports_teams | ~150 (NFL/NBA/MLB/NHL/MLS) |
| `stock_tickers.csv` | stock_tickers | ~500 (S&P 500) |
| `wcag_criteria.csv` | wcag_criteria | ~78 (WCAG 2.1 A/AA/AAA) |
| `regulatory_frameworks.csv` | regulatory_frameworks | ~20 |
| `currency_codes.csv` | currency_codes | ~180 (ISO 4217) |

### CSV Schemas

**sports_teams.csv**
```
team,abbreviation,league,conference_or_division,city,country
```

**stock_tickers.csv**
```
company,ticker,sector,index
```

**wcag_criteria.csv**
```
criterion_id,level,title,description,url
```

**regulatory_frameworks.csv**
```
name,abbreviation,jurisdiction,domain,description
```

**currency_codes.csv**
```
code,name,symbol,countries
```

### Seeding

`priv/repo/seeds.exs` — for each file, check if dictionary with that name
already exists before inserting (idempotent):

```elixir
for file <- Path.wildcard("priv/dictionaries/*.csv") do
  name = Path.basename(file, ".csv")
  unless ExCalibur.Library.get_dictionary_by_name(name) do
    content = File.read!(file)
    ExCalibur.Library.create_dictionary(%{
      name: name,
      content: content,
      content_type: "csv",
      description: "Pre-baked reference dataset"
    })
  end
end
```

## 4. Two Access Modes Stay Separate

| Mode | When to Use | How |
|------|------------|-----|
| Context Provider | Small dicts, always-relevant reference | Injects full content into prompt |
| `query_dictionary` tool | Large dicts, on-demand lookup | Agent calls when needed |

Agents wired to use dictionaries get `query_dictionary` added to their tool
list. The context provider remains for quest steps that need full injection.

## 5. Tool Registration

`query_dictionary` is `@tier :safe` — added to `@safe` list in the tool
registry, available to all members by default.

## 6. What This Does NOT Change

- Dictionary schema unchanged
- Library UI unchanged
- Context provider unchanged
- No "system" flag on pre-baked dictionaries
