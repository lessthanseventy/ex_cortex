# Guild Hall Design

## Concept

Templates are now **Guilds** — pre-built organizations of agents. The app adopts guild terminology throughout the UI.

## Naming Map

| Old | New | Context |
|-----|-----|---------|
| Roles | **Members** | Agents in a guild |
| Pipelines | **Quests** | Structured missions |
| Evaluate | **Evaluate** | Stays — it's a clear action verb |
| Dashboard | **Lodge** | Home base / monitoring |
| Templates | **Charters** | Founding docs that define a guild |
| Middleware | **Rituals** | Steps members always perform |
| Perspectives | **Disciplines** | Areas of expertise |
| — | **Guild Hall** | Browse/install/manage guilds |

## Routes

| Route | LiveView | Nav Label |
|-------|----------|-----------|
| `/` | Redirects to `/lodge` (or `/guild-hall` if empty DB) | — |
| `/guild-hall` | `GuildHallLive` | Guild Hall |
| `/members` | `MembersLive` (was RolesLive) | Members |
| `/members/new` | `MembersLive` :new | — |
| `/members/:id/edit` | `MembersLive` :edit | — |
| `/quests` | `QuestsLive` (was PipelinesLive) | Quests |
| `/evaluate` | `EvaluateLive` | Evaluate |
| `/lodge` | `LodgeLive` (was DashboardLive) | Lodge |

## Guild Hall Page (`/guild-hall`)

- Grid of SaladUI Cards, one per guild charter
- Each card shows:
  - Guild name (e.g., "Content Moderation Guild")
  - Description
  - Member roles as SaladUI Badges
  - Strategy type
  - **"Install Guild"** button
  - **"Dissolve All & Install"** button (with confirmation dialog)
- Installed guilds show a visual indicator (badge/checkmark)
- After install, redirect to configurable destination (default: `/evaluate`)
- First-run: `/` detects zero ResourceDefinitions, redirects to `/guild-hall`

## Renames Within Pages

### Members (was Roles)
- "Add Role" → "Add Member"
- "Edit Role" → "Edit Member"
- "Role Name" → "Member Name"
- "Perspectives" → "Disciplines" in form/display
- Page title: "Members"

### Quests (was Pipelines)
- "Build Pipeline" → "Plan Quest"
- "Templates" section → "Charters"
- "Add Middleware" → "Add Ritual"
- Page title: "Quests"

### Evaluate
- Template picker labels: "Content Moderation Guild" etc.
- Otherwise unchanged

### Lodge (was Dashboard)
- Page title: "Lodge"
- Otherwise same dashboard content

## What Stays Internal

- Module names in ex_cellence library stay unchanged (ResourceDefinition, Excellence.Templates.*, etc.)
- Database tables stay unchanged
- The guild terminology is a UI layer only
- `type == "role"` filter stays — we just display it as "member"

## Config

```elixir
# In GuildHallLive or config
@post_install_redirect "/evaluate"
```
