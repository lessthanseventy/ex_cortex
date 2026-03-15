# Pipeline Builder Design

## Problem

The connection between neurons, ruminations, and synapses isn't discoverable or editable in the UI. There's no way to compose rumination pipelines, configure synapse rosters, or see which neurons will actually run in a given step. All of this is currently managed outside the web UI.

## Solution

An integrated pipeline builder on `/ruminations`, replacing the right panel when in edit mode. TUI aesthetic throughout — box-drawing characters, ASCII fork/merge diagrams, monospace badges.

## Modes

The ruminations page gains two right-panel modes:

- **View** (existing): rumination details, synapse chain preview, run history, ad-hoc run
- **Edit** (new): full pipeline builder with step composition and roster editing

Transitions:
- "Edit" button on view → edit mode
- "New Rumination" button in left panel → edit mode with blank state
- Save/Cancel in edit → back to view mode

## Builder Layout

Three vertically stacked zones:

### Top: Rumination Meta

Editable form for name, description, trigger type (manual/source/scheduled/once/memory/cortex), schedule (if scheduled), source IDs.

### Middle: Step Chain

The main composition area. Vertical chain of step cards connected by ASCII box-drawing lines.

```
  ┌─────────────────────────────────┐
  │ 1. Code Review                  │
  │    ◆ 3 neurons  ▣ gate         │
  │    [▲] [▼] [−]                 │
  └─────────────────────────────────┘
        │
       [+]
        │
  ┌─────────────────────────────────┐
  │ 2. Test Writing                 │
  │    ◆ 1 neuron                  │
  │    [▲] [▼] [−]                 │
  └─────────────────────────────────┘
        │
       [+]
        │
       ╱ ╲  ← branch
      ╱   ╲
  ┌────────┐  ┌────────┐
  │ 3a.    │  │ 3b.    │
  │ Lint   │  │ Audit  │
  └────────┘  └────────┘
      ╲   ╱
       ╲ ╱
  ┌─────────────────────────────────┐
  │ 4. Synthesize (merge)          │
  └─────────────────────────────────┘
        │
       [+]
```

**Step card (compact):** synapse name, neuron count badge, gate indicator, up/down/remove buttons.

**Controls per card:**
- `[▲]` move up, `[▼]` move down, `[−]` remove step
- Click/Enter to expand, Escape to collapse
- Only one card expanded at a time (accordion)

**Inserters:** `[+]` buttons between every pair of cards and at the top/bottom of the chain. Activates the synapse picker inline.

### Bottom: Action Bar

Save, Cancel, Delete rumination.

## Expanded Step Card

When a card is expanded, it shows the full synapse configuration:

**Synapse identity:**
- Name (editable text input)
- Description (editable textarea)
- Shared synapse warning: "Used in N other ruminations" with list on click
- "Duplicate as new synapse" button (creates a clone, swaps the step reference)

**Roster editor:**
Each roster entry is a row:
- `who` — smart picker: type to search by rank (apprentice/journeyman/master), team name (team:Research), specific neuron name, or external model ID (claude_haiku, etc.)
- `when` — sequential / parallel toggle
- `how` — solo / consensus / majority dropdown
- Remove row button, add row button at bottom

**Resolved neuron preview:**
Below the roster, a live-updating list of actual neuron names that match the current roster patterns. Updates as you change `who` values. Helps answer "who will actually run this?"

**Step options:**
- Output type selector
- Gate toggle (halt pipeline on fail verdict)
- Branch toggle (fork into parallel execution)
  - When enabled, prompts to pick/create a synthesizer synapse as the merge point
  - Branch children get their own inserters and ordering controls within the branch group
  - Can convert back to linear (keeps synapses, makes them sequential)

## Synapse Picker

Appears inline at the `[+]` insertion point. Two tabs:

**Existing tab:**
- Searchable list of all synapses
- Each entry shows: name, cluster, neuron count
- Click to insert at that position

**New tab:**
- Minimal form: name + one roster entry
- Creates the synapse and inserts it
- Expand the card afterward to flesh out details

Escape or click-outside to dismiss without inserting.

## Keyboard Navigation

Full keyboard support throughout:
- Arrow keys to move focus between step cards in the chain
- Enter to expand/collapse focused card
- Escape to collapse expanded card or dismiss synapse picker
- Tab through form fields within expanded card and roster editor
- Keyboard shortcuts on up/down/remove buttons (accessible via tab order)
- Synapse picker: type to search, arrow keys to navigate results, Enter to select
- `phx-key` bindings and focus management via `phx-hook` where needed

## Data Model

No schema changes needed. The builder works with existing structures:

- `rumination.steps` — `[%{"step_id" => synapse_id, "order" => n, "type" => "branch"?, "gate" => bool?, "synthesizer" => id?}]`
- `synapse.roster` — `[%{"who" => "...", "when" => "...", "how" => "..."}]`
- Neuron resolution at display time via `ImpulseRunner.resolve_neurons/1` logic (extracted for UI reuse)

## Shared Synapse Handling

Since synapses are standalone entities referenced by ID, editing a synapse in the builder affects all ruminations that use it.

- Show "Used in N other ruminations" notice when expanding a shared synapse
- Offer "Duplicate as new synapse" to create an independent copy
- Editing saves directly to the synapse record

## Implementation Notes

- Extract neuron resolution logic from `ImpulseRunner` into a shared function for live preview
- TUI components: use existing `panel`, `status`, `key_hints` from `ExCortexWeb.Components.TUI`
- Box-drawing characters and ASCII art for pipeline visualization
- LiveView assigns: `editing_rumination`, `pipeline_steps`, `expanded_step`, `synapse_search`, `synapse_picker_position`
- PubSub: broadcast step changes for potential multi-user awareness (future)
