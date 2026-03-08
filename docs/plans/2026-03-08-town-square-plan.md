# Town Square & Page Restructure Plan

**Design doc:** `docs/plans/2026-03-08-town-square-design.md`

---

## Task 1: Member catalogue module

**File:** `lib/ex_calibur/members/member.ex`

**Steps:**
1. Create the Member struct and catalogue with all 18 members across 4 categories, each with system prompts and rank definitions.

**Verify:** `mix compile --warnings-as-errors`

---

## Task 2: Town Square LiveView

**File:** `lib/ex_calibur_web/live/town_square_live.ex`

**Steps:**
1. Create the Town Square page with four sections (Editors, Analysts, Specialists, Advisors).
2. Card grid per section showing member name, category badge, description.
3. Three recruit buttons per card (Apprentice / Journeyman / Master).
4. Clicking rank expands guild picker (same pattern as Library).
5. Recruiting creates a `ResourceDefinition` with status `"draft"` and the selected rank's model/strategy.
6. Disabled state with Guild Hall nudge if no guilds installed.

**Verify:** `mix compile --warnings-as-errors`

---

## Task 3: Quests cleanup

**File:** `lib/ex_calibur_web/live/quests_live.ex`

**Steps:**
1. Remove `@charters` module attribute.
2. Remove `import ExCellenceUI.Components.CharterPicker`.
3. Remove `install_charter` event handler.
4. Remove charter-related assigns from `mount/3`.
5. Remove charter picker from `render/1`.
6. Keep pipeline builder toggle, add/remove middleware, save pipeline.

**Verify:** `mix compile --warnings-as-errors`

---

## Task 4: Router and nav updates

**Files:**
- `lib/ex_calibur_web/router.ex`
- `lib/ex_calibur_web/components/layouts/root.html.heex`

**Steps:**
1. Add `live "/town-square", TownSquareLive, :index` route.
2. Update nav order: Guild Hall → Town Square → Members → Quests → Library → Stacks → Evaluate → Lodge.

**Verify:** `mix compile --warnings-as-errors`

---

## Task 5: Tests

**File:** `test/ex_calibur_web/live/town_square_live_test.exs`

**Steps:**
1. Test page renders with all 4 category sections.
2. Test all 18 member names appear.

**Verify:** `mix test`

---

## Task 6: Full verification

**Steps:**
1. `mix format`
2. `mix compile --warnings-as-errors`
3. `mix test`

**Verify:** All pass cleanly.
