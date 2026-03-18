# Muse Context Intelligence

**Date:** 2026-03-18
**Problem:** Muse fails on natural questions like "do I have anything in my brain dump from this week?" because the Obsidian provider uses rigid trigger words and only reads today's daily note.

---

## 1. Question Classifier (`ExCortex.Muse.Classifier`)

Fast local LLM call (ministral-3:8b) that classifies the question before context gathering.

**Input:** user question string
**Output:** structured map:
```elixir
%{
  providers: ["obsidian", "engrams"],
  time_range: "week",
  obsidian_mode: "daily",
  obsidian_sections: ["brain_dump"],
  search_terms: "brain dump"
}
```

**Known values:**
- `providers`: obsidian, signals, engrams, email, axioms, sources (list, 1+)
- `time_range`: today, yesterday, week, month, all
- `obsidian_mode`: daily, todos, search, list
- `obsidian_sections`: brain_dump, todo, stuff_that_came_up, whats_happening, all
- `search_terms`: free text extracted from question

**Classifier prompt:** Short, constrained — gives the model the vocabulary and asks it to pick. JSON output only. ~200ms on ministral.

**Fallback:** If classifier returns invalid JSON, model is unreachable, or call takes >2s, fall back to current trigger-word `@muse_providers` behavior.

### Files
- New: `lib/ex_cortex/muse/classifier.ex`
- Test: `test/ex_cortex/muse/classifier_test.exs`

---

## 2. Temporal Daily Notes

Expand `gather_daily` in the Obsidian provider to read multiple days based on `time_range`.

**Current:** reads `journal/{today}.md` only
**New:** reads a range of daily notes based on classifier output:
- `today` → 1 note
- `yesterday` → 1 note
- `week` → last 7 notes
- `month` → last 30 notes
- `all` → last 30 (capped)

**Section filtering:** When `obsidian_sections` is not `["all"]`, extract only the matching callout blocks from each note. The daily note template uses Obsidian callout syntax:
```markdown
> [!abstract] brain dump
> you don't have to organize it. just capture it.
> some captured thought here
```

Section extraction: scan for `> [!type] section_name` lines, collect all subsequent `>` prefixed lines until next non-`>` line or next callout.

### Files
- Modify: `lib/ex_cortex/context_providers/obsidian.ex`

---

## 3. Dynamic Provider Selection in Muse

Replace static `@muse_providers` with classifier-driven selection.

**Current flow:**
```
question → gather_context (all 6 providers, trigger-gated) → LLM
```

**New flow:**
```
question → Classifier.classify → build provider configs → ContextProvider.assemble → LLM
```

The classifier output maps to provider configs:
- `"obsidian"` → `%{"type" => "obsidian", "mode" => mode, "time_range" => range, "sections" => sections}`
- `"signals"` → `%{"type" => "signals"}`
- `"engrams"` → `%{"type" => "engrams", "tags" => [], "limit" => 10, "sort" => "top"}`
- `"email"` → `%{"type" => "email", "mode" => "auto"}`
- `"axioms"` → `%{"type" => "axiom_search"}`
- `"sources"` → `%{"type" => "sources"}`

Always include `sources` (cheap inventory) and `engrams` (core memory). Classifier adds/removes the rest.

### Files
- Modify: `lib/ex_cortex/muse.ex` (gather_context)

---

## 4. Obsidian Provider Enhancements

New config keys accepted by the Obsidian provider:
- `"time_range"` — "today", "yesterday", "week", "month"
- `"sections"` — list of section names to extract, or ["all"]
- `"search_terms"` — override search terms from classifier

New private functions:
- `gather_daily_range(time_range)` — reads multiple daily notes
- `extract_sections(note_content, section_names)` — pulls specific callout blocks
- `date_range_for(time_range)` — returns list of date strings

### Files
- Modify: `lib/ex_cortex/context_providers/obsidian.ex`

---

## Implementation Order

1. **Classifier module** — the brain that decides what to fetch
2. **Obsidian temporal + section extraction** — the muscle that reads date ranges and sections
3. **Wire classifier into Muse.gather_context** — connect brain to muscle
4. **Fallback + testing** — ensure graceful degradation
