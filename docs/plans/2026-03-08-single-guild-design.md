# Single Guild Simplification Design

## Overview

Switch from multi-guild to single-guild-per-instance model. One guild active at a time — install a different guild to switch. Simplifies all flows by removing guild pickers.

---

## Current Guild Detection

Derived from installed ResourceDefinitions. `Evaluator.current_guild/0` checks which charter has all its roles present. Returns `{name, module}` or `nil`.

No new schema needed — same detection logic already exists in `installed_guild_names`.

---

## Schema Changes

**Migration:**
- Remove `guild_name` from `excellence_sources`
- Add `book_id` (string, nullable) to `excellence_sources`

**Source schema:** Drop `guild_name`, add `book_id`.
**SourceItem:** Drop `guild_name`.

---

## Page Changes

**Guild Hall:** Always dissolve + install (single guild). Show current guild as active. Remove separate "Dissolve & Install" button.

**Evaluator:** `evaluate/2` drops guild_name arg, uses `current_guild/0`.

**EvaluateLive:** Remove guild picker. Auto-use current guild. Nudge to Guild Hall if none.

**Town Square:** Remove guild picker from recruit. Click rank → create ResourceDefinition directly.

**Library:** Remove guild picker from add. "Add to Stacks" → create Source with `book_id`.

**Stacks:** Show book/scroll name via `book_id` lookup. Remove guild name. Keep pause/resume/delete.

---

## Future

Wire members to sources (who sees what, what actions) is a separate feature built on top of this simplified foundation.
