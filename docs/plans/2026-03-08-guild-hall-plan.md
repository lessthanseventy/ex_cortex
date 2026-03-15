# Guild Hall Implementation Plan

**Design doc:** `docs/plans/2026-03-08-guild-hall-design.md`
**Branch:** `feat/default-use-case`

---

## Task 1: Rename RolesLive → MembersLive (file + module + all strings)

**Files to change:**
- Rename `lib/ex_cortex_web/live/roles_live.ex` → `lib/ex_cortex_web/live/members_live.ex`
- Rename `test/ex_cortex_web/live/roles_live_test.exs` → `test/ex_cortex_web/live/members_live_test.exs`

**Steps:**
1. Create `lib/ex_cortex_web/live/members_live.ex` with module name `ExCortexWeb.MembersLive`
2. In the module: change all user-facing strings:
   - `page_title: "Roles"` → `page_title: "Members"`
   - `page_title: "New Role"` → `page_title: "New Member"`
   - `page_title: "Edit Role"` → `page_title: "Edit Member"`
   - `push_navigate(to: "/roles")` → `push_navigate(to: "/members")` (2 occurrences)
   - `<h1>` text: `"Roles"` → `"Members"`
   - `<.link navigate="/roles/new">` → `<.link navigate="/members/new">`
   - Button text: `"New Role"` → `"New Member"`
   - `navigate={"/roles/#{role.id}/edit"}` → `navigate={"/members/#{role.id}/edit"}`
   - `JS.navigate("/roles")` → `JS.navigate("/members")`
   - Flash: `"Role saved"` → `"Member saved"`
   - Flash: `"Failed to save role"` → `"Failed to save member"`
   - Label in template for perspectives: `"Perspectives"` → `"Disciplines"` (if visible in render — check `.role_form` component from ExCellenceUI)
3. Keep all internal variable names (`roles`, `role_form`, `list_roles`, `get_role`, `save_role` event, `ResourceDefinition` type: "role") unchanged — these are internal
4. Create `test/ex_cortex_web/live/members_live_test.exs`:
   - Module: `ExCortexWeb.MembersLiveTest`
   - Route: `/members`
   - Assert: `"Members"`, `"New Member"`
5. Delete old files: `roles_live.ex`, `roles_live_test.exs`

**Verify:** `mix compile --warnings-as-errors && mix test test/ex_cortex_web/live/members_live_test.exs`

---

## Task 2: Rename PipelinesLive → QuestsLive (file + module + all strings)

**Files to change:**
- Rename `lib/ex_cortex_web/live/pipelines_live.ex` → `lib/ex_cortex_web/live/quests_live.ex`
- Rename `test/ex_cortex_web/live/pipelines_live_test.exs` → `test/ex_cortex_web/live/quests_live_test.exs`

**Steps:**
1. Create `lib/ex_cortex_web/live/quests_live.ex` with module name `ExCortexWeb.QuestsLive`
2. In the module: change all user-facing strings:
   - `page_title: "Pipelines"` → `page_title: "Quests"`
   - `<h1>` text: `"Pipelines"` → `"Quests"`
   - Button text: `"Build Pipeline"` / `"Close Builder"` → `"Plan Quest"` / `"Close Planner"`
   - `<h2>` text: `"Templates"` → `"Charters"`
   - Flash: `"Template '#{template_name}' installed!"` → `"Charter '#{template_name}' installed!"`
   - Flash: `"Template not found"` → `"Charter not found"`
   - Flash: `"Pipeline saved"` → `"Quest saved"`
3. Keep internal variable names unchanged (`@templates`, `pipeline`, `install_template` event name, etc.)
4. Create `test/ex_cortex_web/live/quests_live_test.exs`:
   - Module: `ExCortexWeb.QuestsLiveTest`
   - Route: `/quests`
   - Assert: `"Quests"`, `"Content Moderation"`, `"Code Review"`, `"Risk Assessment"`
5. Delete old files: `pipelines_live.ex`, `pipelines_live_test.exs`

**Verify:** `mix compile --warnings-as-errors && mix test test/ex_cortex_web/live/quests_live_test.exs`

---

## Task 3: Rename DashboardLive → LodgeLive (file + module + all strings)

**Files to change:**
- Rename `lib/ex_cortex_web/live/dashboard_live.ex` → `lib/ex_cortex_web/live/lodge_live.ex`
- Rename `test/ex_cortex_web/live/dashboard_live_test.exs` → `test/ex_cortex_web/live/lodge_live_test.exs`

**Steps:**
1. Create `lib/ex_cortex_web/live/lodge_live.ex` with module name `ExCortexWeb.LodgeLive`
2. In the module: change user-facing strings:
   - `page_title: "Dashboard"` → `page_title: "Lodge"`
   - `<h1>` text: `"Dashboard"` → `"Lodge"`
3. Everything else stays the same (decisions, outcomes, agents — internal data)
4. Create `test/ex_cortex_web/live/lodge_live_test.exs`:
   - Module: `ExCortexWeb.LodgeLiveTest`
   - Route: `/lodge`
   - Assert: `"Lodge"`, `"Recent Decisions"`, `"Agent Health"`
5. Delete old files: `dashboard_live.ex`, `dashboard_live_test.exs`

**Verify:** `mix compile --warnings-as-errors && mix test test/ex_cortex_web/live/lodge_live_test.exs`

---

## Task 4: Update EvaluateLive guild terminology

**File:** `lib/ex_cortex_web/live/evaluate_live.ex`

**Steps:**
1. Change the template display names by appending " Guild" to each:
   - In `mount/3`, where templates are mapped: `{key, meta.name}` → `{key, "#{meta.name} Guild"}`
2. Change the label text: `"Template"` → `"Guild"`
3. No other changes — Evaluate page title stays "Evaluate"

**Verify:** `mix compile --warnings-as-errors && mix test test/ex_cortex_web/live/evaluate_live_test.exs`

---

## Task 5: Update router with new routes and modules

**File:** `lib/ex_cortex_web/router.ex`

**Steps:**
1. Replace the entire route block inside `scope "/"` with:
   ```elixir
   live "/", LodgeLive, :index
   live "/guild-hall", GuildHallLive, :index
   live "/members", MembersLive, :index
   live "/members/new", MembersLive, :new
   live "/members/:id/edit", MembersLive, :edit
   live "/quests", QuestsLive, :index
   live "/quests/new", QuestsLive, :new
   live "/evaluate", EvaluateLive, :index
   live "/lodge", LodgeLive, :index
   ```
2. Note: `GuildHallLive` doesn't exist yet (Task 7). This will cause a compile warning but not an error since Phoenix resolves modules at runtime. To be safe, create a minimal placeholder in this task:
   ```elixir
   # lib/ex_cortex_web/live/guild_hall_live.ex
   defmodule ExCortexWeb.GuildHallLive do
     use ExCortexWeb, :live_view
     def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "Guild Hall")}
     def render(assigns), do: ~H"<h1>Guild Hall</h1><p>Coming soon...</p>"
   end
   ```

**Verify:** `mix compile --warnings-as-errors && mix test`

---

## Task 6: Update nav bar and root layout

**File:** `lib/ex_cortex_web/components/layouts/root.html.heex`

**Steps:**
1. Replace the nav links section with:
   ```heex
   <a href="/guild-hall" class="px-3 py-2 text-sm rounded-md hover:bg-accent text-muted-foreground hover:text-foreground">
     Guild Hall
   </a>
   <a href="/members" class="px-3 py-2 text-sm rounded-md hover:bg-accent text-muted-foreground hover:text-foreground">
     Members
   </a>
   <a href="/quests" class="px-3 py-2 text-sm rounded-md hover:bg-accent text-muted-foreground hover:text-foreground">
     Quests
   </a>
   <a href="/evaluate" class="px-3 py-2 text-sm rounded-md hover:bg-accent text-muted-foreground hover:text-foreground">
     Evaluate
   </a>
   <a href="/lodge" class="px-3 py-2 text-sm rounded-md hover:bg-accent text-muted-foreground hover:text-foreground">
     Lodge
   </a>
   ```

**Verify:** `mix compile --warnings-as-errors && mix test`

---

## Task 7: Build GuildHallLive

**File:** `lib/ex_cortex_web/live/guild_hall_live.ex` (replace placeholder from Task 5)

**Steps:**
1. Create the full `GuildHallLive` module with:
   - `@templates` map (same as PipelinesLive had — reuse `Excellence.Templates.*`)
   - `@post_install_redirect "/evaluate"` module attribute
   - `mount/3`: Load template metadata into `guilds` assign. Also query `ExCortex.Repo.exists?(from r in ResourceDefinition, where: r.type == "role")` to get `installed_types` — a MapSet of installed role names to show checkmarks
   - `handle_event("install_guild", ...)`: Same logic as old `install_template` — write ResourceDefinitions, then `push_navigate(to: @post_install_redirect)`
   - `handle_event("dissolve_and_install", ...)`: Delete all ResourceDefinitions (`Repo.delete_all(ResourceDefinition)`), then install the selected guild's ResourceDefinitions, then redirect
   - `handle_event("confirm_dissolve", %{"guild" => name})`: Set `confirming_dissolve: name` assign to show confirmation state on that card
   - `handle_event("cancel_dissolve", ...)`: Reset `confirming_dissolve: nil`
2. `render/1`: Grid of SaladUI Cards:
   ```heex
   <div class="space-y-6">
     <div class="flex items-center justify-between">
       <h1 class="text-2xl font-bold">Guild Hall</h1>
     </div>
     <p class="text-muted-foreground">Browse and install pre-built guilds — organizations of agents with specialized expertise.</p>
     <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
       <%= for guild <- @guilds do %>
         <.card>
           <.card_header>
             <div class="flex items-center justify-between">
               <.card_title>{guild.name} Guild</.card_title>
               <%= if MapSet.member?(@installed_names, guild.name) do %>
                 <.badge variant="default">Installed</.badge>
               <% end %>
             </div>
             <.card_description>{guild.description}</.card_description>
           </.card_header>
           <.card_content>
             <div class="space-y-2">
               <p class="text-sm font-medium">Members</p>
               <div class="flex flex-wrap gap-1">
                 <%= for role <- guild.roles do %>
                   <.badge variant="outline">{role}</.badge>
                 <% end %>
               </div>
               <p class="text-sm text-muted-foreground mt-2">Strategy: {guild.strategy}</p>
             </div>
           </.card_content>
           <.card_footer>
             <div class="flex gap-2">
               <%= if @confirming_dissolve == guild.name do %>
                 <.button variant="destructive" phx-click="dissolve_and_install" phx-value-guild={guild.name}>
                   Confirm Dissolve & Install
                 </.button>
                 <.button variant="outline" phx-click="cancel_dissolve">Cancel</.button>
               <% else %>
                 <.button phx-click="install_guild" phx-value-guild={guild.name}>
                   Install Guild
                 </.button>
                 <.button variant="outline" phx-click="confirm_dissolve" phx-value-guild={guild.name}>
                   Dissolve All & Install
                 </.button>
               <% end %>
             </div>
           </.card_footer>
         </.card>
       <% end %>
     </div>
   </div>
   ```
3. Import `SaladUI.Card`, `SaladUI.Badge`, alias `Excellence.Schemas.ResourceDefinition`

**Verify:** `mix compile --warnings-as-errors`

---

## Task 8: Add GuildHallLive test

**File:** `test/ex_cortex_web/live/guild_hall_live_test.exs`

**Steps:**
1. Create test module `ExCortexWeb.GuildHallLiveTest`:
   ```elixir
   defmodule ExCortexWeb.GuildHallLiveTest do
     use ExCortexWeb.ConnCase, async: true
     import Phoenix.LiveViewTest

     describe "index" do
       test "renders guild hall with available guilds", %{conn: conn} do
         {:ok, _view, html} = live(conn, "/guild-hall")
         assert html =~ "Guild Hall"
         assert html =~ "Content Moderation"
         assert html =~ "Code Review"
         assert html =~ "Risk Assessment"
         assert html =~ "Install Guild"
       end
     end
   end
   ```

**Verify:** `mix test test/ex_cortex_web/live/guild_hall_live_test.exs`

---

## Task 9: Add first-run redirect on `/` (LodgeLive)

**File:** `lib/ex_cortex_web/live/lodge_live.ex`

**Steps:**
1. In `mount/3`, after `load_dashboard_data`, add first-run detection:
   ```elixir
   def mount(_params, _session, socket) do
     import Ecto.Query
     has_roles = ExCortex.Repo.exists?(from r in ResourceDefinition, where: r.type == "role")

     if !has_roles && socket.assigns.live_action == :index do
       {:ok, push_navigate(socket, to: "/guild-hall")}
     else
       if connected?(socket) do
         Phoenix.PubSub.subscribe(ExCortex.PubSub, "evaluation:results")
         :timer.send_interval(30_000, self(), :refresh)
       end
       {:ok, load_dashboard_data(socket)}
     end
   end
   ```
2. Add `alias Excellence.Schemas.ResourceDefinition` at the top of the module

**Verify:** `mix compile --warnings-as-errors && mix test`

---

## Task 10: Update CLAUDE.md and run full verification

**Files:** `CLAUDE.md`

**Steps:**
1. Update route documentation in CLAUDE.md to reflect new routes
2. Update any references to "roles" → "members", "pipelines" → "quests", "dashboard" → "lodge"
3. Add Guild Hall to the architecture description
4. Run full test suite: `mix test`
5. Run format check: `mix format --check-formatted`
6. Compile with warnings as errors: `mix compile --warnings-as-errors`

**Verify:** All three commands pass cleanly.
