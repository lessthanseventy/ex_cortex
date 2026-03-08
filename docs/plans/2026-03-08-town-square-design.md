# Town Square & Page Restructure Design

## Overview

Add a Town Square page for recruiting individual members (standalone roles not tied to guilds). Reorganize pages to eliminate overlap between Quests and Guild Hall. Introduce apprentice/journeyman/master rank tiers mapping to model capability.

---

## Page Structure

| Page | URL | Purpose |
|------|-----|---------|
| Lodge | `/` | Dashboard |
| Guild Hall | `/guild-hall` | Browse & install pre-built guild packages |
| Town Square | `/town-square` | Browse & recruit individual members |
| Members | `/members` | Manage installed members (from Guild Hall or Town Square) |
| Quests | `/quests` | Pipeline builder only (charter browsing removed) |
| Library | `/library` | Browse scrolls & books |
| Stacks | `/stacks` | Manage active sources |
| Evaluate | `/evaluate` | Run evaluations |

Nav order: Guild Hall → Town Square → Members → Quests → Library → Stacks → Evaluate → Lodge

---

## Rank Tiers

Each member is available at three ranks, mapping to model capability:

- **Apprentice** — phi4-mini / Haiku (fast, cheap, cot strategy)
- **Journeyman** — gemma3:4b / Sonnet (thorough, cod strategy)
- **Master** — llama3:8b / Opus (most capable, cod strategy)

Provider (Ollama vs Claude API) is orthogonal to rank — a config choice, not a rank choice.

---

## Member Roster

### Editors (text quality)

1. **grammar-editor** — Spelling, grammar, punctuation accuracy
2. **tone-reviewer** — Formal/casual/professional consistency
3. **style-guide-enforcer** — AP, Chicago, house style adherence
4. **brevity-coach** — Wordiness, concision, signal-to-noise ratio
5. **technical-writer** — Clarity, structure, audience-appropriate complexity

### Analysts (data & patterns)

1. **trend-spotter** — Patterns, anomalies, emerging signals in data
2. **sentiment-analyzer** — Emotional tone, brand perception, audience reaction
3. **data-quality-auditor** — Completeness, consistency, accuracy of datasets
4. **competitive-analyst** — Market positioning, competitor comparison

### Specialists (domain expertise)

1. **i18n-checker** — Internationalization, locale handling, character encoding
2. **regex-reviewer** — Pattern correctness, edge cases, performance
3. **api-design-critic** — REST conventions, naming, versioning, error handling
4. **sql-reviewer** — Query efficiency, indexing, normalization
5. **documentation-auditor** — Completeness, accuracy, examples, API docs

### Advisors (perspective & judgment)

1. **devils-advocate** — Challenges assumptions, finds counterarguments
2. **compliance-officer** — Regulatory requirements, policy adherence
3. **ux-advocate** — User impact, usability, accessibility concerns
4. **security-skeptic** — Trust boundaries, attack surface, data exposure

18 members × 3 ranks = 54 recruitable options.

---

## Data Model

### Member struct

```elixir
defmodule ExCalibur.Members.Member do
  defstruct [:id, :name, :description, :category, :system_prompt, :ranks]
end
```

`ranks` contains model/strategy per tier:

```elixir
%{
  apprentice: %{model: "phi4-mini", strategy: "cot"},
  journeyman: %{model: "gemma3:4b", strategy: "cod"},
  master: %{model: "llama3:8b", strategy: "cod"}
}
```

### Catalogue functions

- `Member.all/0` — all members
- `Member.editors/0`, `Member.analysts/0`, `Member.specialists/0`, `Member.advisors/0`
- `Member.get/1` — by id

### Recruiting flow

Recruit = pick member + rank → pick guild → creates `ResourceDefinition` with:
- `type: "role"`
- `name: member.name`
- `status: "draft"`
- `config.system_prompt` from member blueprint
- `config.perspectives` with single perspective at chosen rank's model/strategy

Same member can be recruited at multiple ranks for different use cases.

---

## Town Square Page

- Four sections: Editors, Analysts, Specialists, Advisors
- Card grid per section with member name, category badge, description
- Three recruit buttons per card: Apprentice / Journeyman / Master
- Clicking rank expands guild picker (same Library pattern)
- Disabled with Guild Hall nudge if no guilds installed

---

## Quests Cleanup

Remove `@charters` map, `install_charter` handler, and `CharterPicker` import from `quests_live.ex`. Keep only the pipeline builder toggle, add/remove middleware, and save pipeline.

---

## Implementation Notes

- Member catalogue in `lib/ex_calibur/members/member.ex`
- Town Square LiveView in `lib/ex_calibur_web/live/town_square_live.ex`
- Update router, nav layout, and tests
- Each member needs a tailored system prompt
