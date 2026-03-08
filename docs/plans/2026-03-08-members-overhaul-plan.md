# Members Page Overhaul Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the Members LiveView to show built-in and custom members in one unified collapsible-card list with inline editing and copper/silver/gold rank colors.

**Architecture:** Merge `Member.all()` (built-in structs) with `ResourceDefinition` DB rows at query time. Built-ins get a DB record (source: "code", config["member_id"] = slug) when first toggled/edited. Custom members are source: "db" with no member_id. The LiveView manages per-card expand/collapse state client-side via assigns.

**Tech Stack:** Phoenix LiveView, SaladUI (Card, Badge, Button, Input, Textarea), Tailwind CSS, Ecto/ResourceDefinition schema, ExCalibur.Members.Member built-in catalog

**Worktree:** `.worktrees/members-overhaul` on branch `feature/members-overhaul`

---

## Background: Key Files and Schemas

### Built-in members — `lib/ex_calibur/members/member.ex`
`Member.all()` returns a list of `%Member{}` structs with fields:
- `id` (string slug, e.g. "grammar-editor")
- `name`, `description`, `category` (atom: :editor/:analyst/:specialist/:advisor)
- `system_prompt` (string)
- `ranks` (map with atom keys: `%{apprentice: %{model: "phi4-mini", strategy: "cot"}, journeyman: ..., master: ...}`)

### DB members — `Excellence.Schemas.ResourceDefinition`
Schema in `deps`-adjacent `ex_cellence` library. Fields: `id` (UUID), `type`, `name`, `status`, `source`, `config` (map), `version`, `created_by`, timestamps.
- Valid statuses: `"draft" "shadow" "active" "paused" "archived"`
- Valid sources: `"code" "db" "frozen"`
- Unique constraint on `[:type, :name]`
- `active` means `status == "active"`

### How built-ins are persisted
When a built-in is toggled on or edited, upsert a `ResourceDefinition` with:
```elixir
%{
  type: "role",
  name: <member.name>,       # e.g. "Grammar Editor"
  source: "code",
  status: "active",
  config: %{
    "member_id" => "grammar-editor",   # links back to built-in slug
    "system_prompt" => "...",
    "ranks" => %{
      "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
      "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
      "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
    }
  }
}
```

### How custom members are persisted
```elixir
%{
  type: "role",
  name: "My Custom Member",
  source: "db",
  status: "active",
  config: %{
    "system_prompt" => "...",
    "ranks" => %{
      "apprentice" => %{"model" => "", "strategy" => "cot"},
      ...
    }
  }
}
```

### Unified member map (used everywhere in the LiveView)
```elixir
%{
  id: "grammar-editor",        # built-in slug OR UUID string for custom
  name: "Grammar Editor",
  description: "...",          # nil for custom
  category: :editor,           # nil for custom
  builtin: true,               # false for custom
  active: true,
  system_prompt: "...",
  ranks: %{
    apprentice: %{model: "phi4-mini", strategy: "cot"},
    journeyman: %{model: "gemma3:4b", strategy: "cod"},
    master: %{model: "llama3:8b", strategy: "cod"}
  },
  db_id: "uuid-or-nil"         # nil for built-ins not yet in DB
}
```

### Current test file
`test/ex_calibur_web/live/members_live_test.exs` — currently has one trivial test. You will rewrite it.

---

## Task 1: Add merge helper to members_live.ex

**Files:**
- Modify: `lib/ex_calibur_web/live/members_live.ex`

This task adds a private `list_members/0` function that returns a sorted list of unified member maps. No UI changes yet.

**Step 1: Write the failing test**

Replace contents of `test/ex_calibur_web/live/members_live_test.exs`:

```elixir
defmodule ExCaliburWeb.MembersLiveTest do
  use ExCaliburWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Excellence.Schemas.ResourceDefinition
  alias ExCalibur.Repo

  describe "list_members merge" do
    test "renders built-in members on the page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/members")
      # Grammar Editor is a built-in member
      assert html =~ "Grammar Editor"
    end

    test "built-in members show as inactive by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/members")
      # Should show toggle in off state — look for inactive indicator
      # The page renders all built-ins; with no DB record they are inactive
      assert html =~ "Grammar Editor"
    end

    test "custom DB member appears on page", %{conn: conn} do
      {:ok, _} =
        Repo.insert(%ResourceDefinition{
          type: "role",
          name: "My Custom Role",
          source: "db",
          status: "active",
          config: %{
            "system_prompt" => "You are custom.",
            "ranks" => %{
              "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
              "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
              "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
            }
          }
        })

      {:ok, _view, html} = live(conn, "/members")
      assert html =~ "My Custom Role"
    end

    test "active members appear before inactive ones", %{conn: conn} do
      {:ok, _} =
        Repo.insert(%ResourceDefinition{
          type: "role",
          name: "Grammar Editor",
          source: "code",
          status: "active",
          config: %{
            "member_id" => "grammar-editor",
            "system_prompt" => "You are a grammar editor.",
            "ranks" => %{
              "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
              "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
              "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
            }
          }
        })

      {:ok, _view, html} = live(conn, "/members")
      # Grammar Editor is now active — it should appear before inactive built-ins
      grammar_pos = :binary.match(html, "Grammar Editor") |> elem(0)
      tone_pos = :binary.match(html, "Tone Reviewer") |> elem(0)
      assert grammar_pos < tone_pos
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul && mix test test/ex_calibur_web/live/members_live_test.exs 2>&1 | tail -20
```

Expected: failures — "Grammar Editor" not found (built-ins not rendered yet).

**Step 3: Add `list_members/0` to members_live.ex**

Add these private functions to `lib/ex_calibur_web/live/members_live.ex`, replacing the existing `list_roles/0` and `get_role/1`:

```elixir
defp list_members do
  import Ecto.Query

  db_roles =
    ExCalibur.Repo.all(from(r in ResourceDefinition, where: r.type == "role"))

  db_by_member_id =
    db_roles
    |> Enum.filter(&(&1.config["member_id"] != nil))
    |> Map.new(&{&1.config["member_id"], &1})

  db_custom =
    Enum.filter(db_roles, &(&1.config["member_id"] == nil))

  builtins =
    ExCalibur.Members.Member.all()
    |> Enum.map(fn m ->
      db = Map.get(db_by_member_id, m.id)
      to_unified(m, db)
    end)

  customs =
    Enum.map(db_custom, &to_unified_custom/1)

  (builtins ++ customs)
  |> Enum.sort_by(fn m -> {if(m.active, do: 0, else: 1), if(m.builtin, do: 0, else: 1), m.name} end)
end

defp to_unified(%ExCalibur.Members.Member{} = m, nil) do
  %{
    id: m.id,
    name: m.name,
    description: m.description,
    category: m.category,
    builtin: true,
    active: false,
    system_prompt: m.system_prompt,
    ranks: %{
      apprentice: m.ranks[:apprentice] || %{model: "", strategy: "cot"},
      journeyman: m.ranks[:journeyman] || %{model: "", strategy: "cod"},
      master: m.ranks[:master] || %{model: "", strategy: "cod"}
    },
    db_id: nil
  }
end

defp to_unified(%ExCalibur.Members.Member{} = m, db) do
  %{
    id: m.id,
    name: m.name,
    description: m.description,
    category: m.category,
    builtin: true,
    active: db.status == "active",
    system_prompt: db.config["system_prompt"] || m.system_prompt,
    ranks: %{
      apprentice: parse_rank(db.config["ranks"]["apprentice"], m.ranks[:apprentice]),
      journeyman: parse_rank(db.config["ranks"]["journeyman"], m.ranks[:journeyman]),
      master: parse_rank(db.config["ranks"]["master"], m.ranks[:master])
    },
    db_id: db.id
  }
end

defp to_unified_custom(db) do
  %{
    id: db.id,
    name: db.name,
    description: nil,
    category: nil,
    builtin: false,
    active: db.status == "active",
    system_prompt: db.config["system_prompt"] || "",
    ranks: %{
      apprentice: parse_rank(db.config["ranks"]["apprentice"], %{model: "", strategy: "cot"}),
      journeyman: parse_rank(db.config["ranks"]["journeyman"], %{model: "", strategy: "cod"}),
      master: parse_rank(db.config["ranks"]["master"], %{model: "", strategy: "cod"})
    },
    db_id: db.id
  }
end

defp parse_rank(nil, default), do: default
defp parse_rank(r, _default), do: %{model: r["model"] || "", strategy: r["strategy"] || "cot"}
```

Also update `mount/3` to use `list_members/0`:

```elixir
def mount(_params, _session, socket) do
  members = list_members()
  {:ok, assign(socket, members: members, expanded: MapSet.new(), adding_new: false)}
end
```

**Step 4: Run tests**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul && mix test test/ex_calibur_web/live/members_live_test.exs 2>&1 | tail -20
```

Expected: tests pass (built-ins are now in `@members` assign and will be rendered in next task).

**Step 5: Commit**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul
git add lib/ex_calibur_web/live/members_live.ex test/ex_calibur_web/live/members_live_test.exs
git commit -m "feat: add list_members merge of built-ins and DB roles"
```

---

## Task 2: Rewrite the render/1 with collapsible card UI

**Files:**
- Modify: `lib/ex_calibur_web/live/members_live.ex`

Replace the entire `render/1` function and add a new `member_card/1` component. Remove the old `role_form` import and `@editing` assign references.

**Step 1: Write failing test for UI structure**

Add to `test/ex_calibur_web/live/members_live_test.exs`:

```elixir
describe "card UI" do
  test "shows + button to add new member", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/members")
    assert html =~ "phx-click=\"add_new\""
  end

  test "built-in member shows rank pills", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/members")
    assert html =~ "Apprentice"
    assert html =~ "Journeyman"
    assert html =~ "Master"
  end

  test "clicking member name expands it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/members")
    # Click to expand Grammar Editor (a built-in)
    html = view |> element("[phx-click=\"toggle_expand\"][phx-value-id=\"grammar-editor\"]") |> render_click()
    assert html =~ "system_prompt"
  end
end
```

**Step 2: Run test to verify it fails**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul && mix test test/ex_calibur_web/live/members_live_test.exs 2>&1 | tail -20
```

Expected: fail — elements not found.

**Step 3: Rewrite render/1 and add member_card/1**

Replace the `render/1` function in `lib/ex_calibur_web/live/members_live.ex`:

```elixir
@impl true
def render(assigns) do
  ~H"""
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <h1 class="text-2xl font-bold">Members</h1>
      <.button variant="outline" size="sm" phx-click="add_new">+ New Member</.button>
    </div>

    <%= if @adding_new do %>
      <.new_member_card />
    <% end %>

    <div class="space-y-2">
      <.member_card
        :for={member <- @members}
        member={member}
        expanded={MapSet.member?(@expanded, member.id)}
      />
    </div>
  </div>
  """
end

attr :member, :map, required: true
attr :expanded, :boolean, required: true

defp member_card(assigns) do
  ~H"""
  <div class={["border rounded-lg bg-card transition-opacity", if(!@member.active, do: "opacity-60")]}>
    <%!-- Collapsed header (always visible) --%>
    <div class="flex items-center gap-3 px-4 py-3 cursor-pointer"
         phx-click="toggle_expand"
         phx-value-id={@member.id}>
      <span class={["transition-transform text-muted-foreground", if(@expanded, do: "rotate-90")]}>›</span>
      <div class="flex-1 flex items-center gap-2 min-w-0">
        <span class="font-medium truncate">{@member.name}</span>
        <%= if @member.category do %>
          <.badge variant="outline" class="text-xs shrink-0">{@member.category}</.badge>
        <% end %>
      </div>
      <div class="flex items-center gap-2 shrink-0">
        <.rank_pill rank={:apprentice} model={@member.ranks.apprentice.model} />
        <.rank_pill rank={:journeyman} model={@member.ranks.journeyman.model} />
        <.rank_pill rank={:master} model={@member.ranks.master.model} />
        <button
          class="relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50"
          style={"background-color: #{if @member.active, do: "hsl(var(--primary))", else: "hsl(var(--input))"}"}
          phx-click="toggle_active"
          phx-value-id={@member.id}
          phx-value-active={if @member.active, do: "true", else: "false"}
          type="button"
        >
          <span
            class="pointer-events-none inline-block h-4 w-4 rounded-full bg-background shadow-lg ring-0 transition-transform"
            style={"transform: translateX(#{if @member.active, do: "16px", else: "0px"})"}
          ></span>
        </button>
      </div>
    </div>

    <%!-- Expanded body --%>
    <%= if @expanded do %>
      <div class="border-t px-4 py-4">
        <form phx-submit="save_member" class="space-y-4">
          <input type="hidden" name="member[id]" value={@member.id} />
          <input type="hidden" name="member[builtin]" value={if @member.builtin, do: "true", else: "false"} />

          <%= if !@member.builtin do %>
            <div>
              <label class="text-sm font-medium">Name</label>
              <.input type="text" name="member[name]" value={@member.name} />
            </div>
          <% end %>

          <div>
            <label class="text-sm font-medium">System Prompt</label>
            <.textarea name="member[system_prompt]" value={@member.system_prompt} rows={5} />
          </div>

          <div class="grid grid-cols-3 gap-3">
            <.rank_section rank={:apprentice} data={@member.ranks.apprentice} />
            <.rank_section rank={:journeyman} data={@member.ranks.journeyman} />
            <.rank_section rank={:master} data={@member.ranks.master} />
          </div>

          <div class="flex justify-between pt-2">
            <.button type="button" variant="destructive" size="sm"
              phx-click="delete_member" phx-value-id={@member.id}
              data-confirm="Delete this member?">
              Delete
            </.button>
            <.button type="submit" size="sm">Save</.button>
          </div>
        </form>
      </div>
    <% end %>
  </div>
  """
end

defp new_member_card(assigns) do
  ~H"""
  <div class="border rounded-lg bg-card border-dashed">
    <div class="px-4 py-4">
      <form phx-submit="create_member" class="space-y-4">
        <div>
          <label class="text-sm font-medium">Name</label>
          <.input type="text" name="member[name]" value="" placeholder="e.g. safety-reviewer" />
        </div>
        <div>
          <label class="text-sm font-medium">System Prompt</label>
          <.textarea name="member[system_prompt]" value="" rows={4} placeholder="You are a..." />
        </div>
        <div class="grid grid-cols-3 gap-3">
          <.rank_section rank={:apprentice} data={%{model: "", strategy: "cot"}} />
          <.rank_section rank={:journeyman} data={%{model: "", strategy: "cod"}} />
          <.rank_section rank={:master} data={%{model: "", strategy: "cod"}} />
        </div>
        <div class="flex justify-end gap-2 pt-2">
          <.button type="button" variant="outline" size="sm" phx-click="cancel_new">Cancel</.button>
          <.button type="submit" size="sm">Create Member</.button>
        </div>
      </form>
    </div>
  </div>
  """
end

attr :rank, :atom, required: true
attr :model, :string, required: true

defp rank_pill(assigns) do
  color_classes =
    case assigns.rank do
      :apprentice -> "border-l-2 border-amber-700 bg-amber-50 text-amber-700"
      :journeyman -> "border-l-2 border-slate-400 bg-slate-100 text-slate-500"
      :master -> "border-l-2 border-yellow-500 bg-yellow-50 text-yellow-600"
    end

  label =
    case assigns.rank do
      :apprentice -> "A"
      :journeyman -> "J"
      :master -> "M"
    end

  assigns = assign(assigns, color_classes: color_classes, label: label)

  ~H"""
  <span class={["flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium", @color_classes]}>
    <span class="font-bold">{@label}</span>
    <span class="opacity-75 max-w-20 truncate">{if @model == "", do: "—", else: @model}</span>
  </span>
  """
end

attr :rank, :atom, required: true
attr :data, :map, required: true

defp rank_section(assigns) do
  {label, border_class, text_class} =
    case assigns.rank do
      :apprentice -> {"Apprentice", "border-t-2 border-amber-700", "text-amber-700"}
      :journeyman -> {"Journeyman", "border-t-2 border-slate-400", "text-slate-500"}
      :master -> {"Master", "border-t-2 border-yellow-500", "text-yellow-600"}
    end

  rank_key = Atom.to_string(assigns.rank)
  assigns = assign(assigns, label: label, border_class: border_class, text_class: text_class, rank_key: rank_key)

  ~H"""
  <div class={["rounded p-3 bg-muted/30", @border_class]}>
    <div class={["text-xs font-semibold mb-2", @text_class]}>{@label}</div>
    <div class="space-y-1">
      <.input
        type="text"
        name={"member[ranks][#{@rank_key}][model]"}
        value={@data.model}
        placeholder="model name"
        class="text-sm"
      />
      <select name={"member[ranks][#{@rank_key}][strategy]"}
        class="w-full text-sm border rounded px-2 py-1 bg-background">
        <option value="cot" selected={@data.strategy == "cot"}>cot</option>
        <option value="cod" selected={@data.strategy == "cod"}>cod</option>
        <option value="default" selected={@data.strategy == "default"}>default</option>
      </select>
    </div>
  </div>
  """
end
```

Also update the module-level imports — remove the `RoleForm` import, add `SaladUI.Input` and `SaladUI.Textarea`:

```elixir
import SaladUI.Badge
import SaladUI.Button
import SaladUI.Card
import SaladUI.Input
import SaladUI.Textarea
```

Remove: `import ExCellenceUI.Components.RoleForm`

**Step 4: Run tests**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul && mix test test/ex_calibur_web/live/members_live_test.exs 2>&1 | tail -30
```

Expected: all tests pass.

**Step 5: Compile check**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul && mix compile --warnings-as-errors 2>&1 | tail -20
```

Expected: no warnings, no errors.

**Step 6: Commit**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul
git add lib/ex_calibur_web/live/members_live.ex test/ex_calibur_web/live/members_live_test.exs
git commit -m "feat: rewrite members UI with collapsible rank cards"
```

---

## Task 3: Wire up all LiveView events

**Files:**
- Modify: `lib/ex_calibur_web/live/members_live.ex`

Replace all existing `handle_event` callbacks and update `handle_params`/`apply_action` to remove the old `:new`/`:edit` live actions (navigation-based editing is gone — everything is inline now).

**Step 1: Write failing tests for events**

Add to `test/ex_calibur_web/live/members_live_test.exs`:

```elixir
describe "events" do
  test "toggle_expand adds member to expanded set", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/members")
    html = view |> element("[phx-click=\"toggle_expand\"][phx-value-id=\"grammar-editor\"]") |> render_click()
    # system_prompt textarea is visible when expanded
    assert html =~ "system_prompt"
  end

  test "toggle_expand collapses when already expanded", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/members")
    view |> element("[phx-click=\"toggle_expand\"][phx-value-id=\"grammar-editor\"]") |> render_click()
    html = view |> element("[phx-click=\"toggle_expand\"][phx-value-id=\"grammar-editor\"]") |> render_click()
    refute html =~ "member[system_prompt]"
  end

  test "toggle_active activates a built-in member", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/members")
    view
    |> element("[phx-click=\"toggle_active\"][phx-value-id=\"grammar-editor\"]")
    |> render_click(%{"id" => "grammar-editor", "active" => "false"})

    # Verify DB record was created
    import Ecto.Query
    db = ExCalibur.Repo.one(
      from r in ResourceDefinition,
      where: r.type == "role" and r.source == "code"
    )
    assert db != nil
    assert db.status == "active"
    assert db.config["member_id"] == "grammar-editor"
  end

  test "add_new shows new member form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/members")
    html = view |> element("[phx-click=\"add_new\"]") |> render_click()
    assert html =~ "Create Member"
  end

  test "cancel_new hides new member form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/members")
    view |> element("[phx-click=\"add_new\"]") |> render_click()
    html = view |> element("[phx-click=\"cancel_new\"]") |> render_click()
    refute html =~ "Create Member"
  end

  test "create_member inserts a new custom member", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/members")
    view |> element("[phx-click=\"add_new\"]") |> render_click()

    html =
      view
      |> form("form[phx-submit=\"create_member\"]", %{
        "member" => %{
          "name" => "Test Role",
          "system_prompt" => "You test things.",
          "ranks" => %{
            "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
            "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
            "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
          }
        }
      })
      |> render_submit()

    assert html =~ "Test Role"
  end

  test "save_member updates an existing built-in", %{conn: conn} do
    # First activate it so there's a DB record
    {:ok, rddef} =
      ExCalibur.Repo.insert(%ResourceDefinition{
        type: "role",
        name: "Grammar Editor",
        source: "code",
        status: "active",
        config: %{
          "member_id" => "grammar-editor",
          "system_prompt" => "Old prompt",
          "ranks" => %{
            "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
            "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
            "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
          }
        }
      })

    {:ok, view, _html} = live(conn, "/members")

    view
    |> form("form[phx-submit=\"save_member\"]", %{
      "member" => %{
        "id" => "grammar-editor",
        "builtin" => "true",
        "system_prompt" => "Updated prompt.",
        "ranks" => %{
          "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
          "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
          "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
        }
      }
    })
    |> render_submit()

    updated = ExCalibur.Repo.get!(ResourceDefinition, rddef.id)
    assert updated.config["system_prompt"] == "Updated prompt."
  end

  test "delete_member removes a custom member", %{conn: conn} do
    {:ok, _} =
      ExCalibur.Repo.insert(%ResourceDefinition{
        type: "role",
        name: "Deletable Role",
        source: "db",
        status: "active",
        config: %{
          "system_prompt" => "gone",
          "ranks" => %{
            "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
            "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
            "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
          }
        }
      })

    {:ok, view, _html} = live(conn, "/members")
    html = view |> element("[phx-click=\"toggle_expand\"]", "Deletable Role") |> render_click()
    assert html =~ "Deletable Role"

    # trigger delete via JS confirm bypass
    view
    |> element("[phx-click=\"delete_member\"]")
    |> render_click(%{"id" => to_string(ExCalibur.Repo.get_by!(ResourceDefinition, name: "Deletable Role").id)})

    refute render(view) =~ "Deletable Role"
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul && mix test test/ex_calibur_web/live/members_live_test.exs 2>&1 | tail -30
```

Expected: most event tests fail — handlers don't exist yet.

**Step 3: Replace all handle_event callbacks and update mount/handle_params**

Replace ALL existing `handle_event` implementations and update `mount/3` and `apply_action/3` in `lib/ex_calibur_web/live/members_live.ex`:

```elixir
@impl true
def mount(_params, _session, socket) do
  {:ok, assign(socket, members: list_members(), expanded: MapSet.new(), adding_new: false)}
end

@impl true
def handle_params(_params, _url, socket) do
  {:noreply, assign(socket, page_title: "Members")}
end

@impl true
def handle_event("toggle_expand", %{"id" => id}, socket) do
  expanded =
    if MapSet.member?(socket.assigns.expanded, id) do
      MapSet.delete(socket.assigns.expanded, id)
    else
      MapSet.put(socket.assigns.expanded, id)
    end

  {:noreply, assign(socket, expanded: expanded)}
end

@impl true
def handle_event("toggle_active", %{"id" => id, "active" => current_active}, socket) do
  new_active = current_active != "true"

  upsert_member_active(id, new_active, socket.assigns.members)

  {:noreply, assign(socket, members: list_members())}
end

@impl true
def handle_event("add_new", _params, socket) do
  {:noreply, assign(socket, adding_new: true)}
end

@impl true
def handle_event("cancel_new", _params, socket) do
  {:noreply, assign(socket, adding_new: false)}
end

@impl true
def handle_event("create_member", %{"member" => params}, socket) do
  attrs = %{
    type: "role",
    name: params["name"],
    source: "db",
    status: "active",
    config: %{
      "system_prompt" => params["system_prompt"] || "",
      "ranks" => parse_ranks(params["ranks"])
    }
  }

  case %ResourceDefinition{} |> ResourceDefinition.changeset(attrs) |> ExCalibur.Repo.insert() do
    {:ok, _} ->
      {:noreply, assign(socket, members: list_members(), adding_new: false)}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Failed to create member")}
  end
end

@impl true
def handle_event("save_member", %{"member" => params}, socket) do
  builtin = params["builtin"] == "true"
  id = params["id"]

  result =
    if builtin do
      save_builtin_member(id, params, socket.assigns.members)
    else
      save_custom_member(id, params)
    end

  case result do
    {:ok, _} ->
      {:noreply, assign(socket, members: list_members())}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Failed to save member")}
  end
end

@impl true
def handle_event("delete_member", %{"id" => id}, socket) do
  case ExCalibur.Repo.get(ResourceDefinition, id) do
    nil ->
      {:noreply, socket}

    resource ->
      ExCalibur.Repo.delete(resource)
      {:noreply, assign(socket, members: list_members())}
  end
end

# Private helpers

defp upsert_member_active(id, new_active, members) do
  status = if new_active, do: "active", else: "draft"
  member = Enum.find(members, &(&1.id == id))

  if member && member.builtin do
    builtin = ExCalibur.Members.Member.get(id)

    case member.db_id && ExCalibur.Repo.get(ResourceDefinition, member.db_id) do
      nil ->
        %ResourceDefinition{}
        |> ResourceDefinition.changeset(%{
          type: "role",
          name: builtin.name,
          source: "code",
          status: status,
          config: %{
            "member_id" => id,
            "system_prompt" => builtin.system_prompt,
            "ranks" => ranks_to_config(builtin.ranks)
          }
        })
        |> ExCalibur.Repo.insert()

      db ->
        db
        |> ResourceDefinition.changeset(%{status: status})
        |> ExCalibur.Repo.update()
    end
  else
    case ExCalibur.Repo.get(ResourceDefinition, id) do
      nil -> {:ok, nil}
      db -> db |> ResourceDefinition.changeset(%{status: status}) |> ExCalibur.Repo.update()
    end
  end
end

defp save_builtin_member(slug, params, members) do
  builtin = ExCalibur.Members.Member.get(slug)
  member = Enum.find(members, &(&1.id == slug))

  config = %{
    "member_id" => slug,
    "system_prompt" => params["system_prompt"] || "",
    "ranks" => parse_ranks(params["ranks"])
  }

  case member && member.db_id && ExCalibur.Repo.get(ResourceDefinition, member.db_id) do
    nil ->
      %ResourceDefinition{}
      |> ResourceDefinition.changeset(%{
        type: "role",
        name: builtin.name,
        source: "code",
        status: "active",
        config: config
      })
      |> ExCalibur.Repo.insert()

    db ->
      db
      |> ResourceDefinition.changeset(%{config: config})
      |> ExCalibur.Repo.update()
  end
end

defp save_custom_member(id, params) do
  case ExCalibur.Repo.get(ResourceDefinition, id) do
    nil ->
      {:error, :not_found}

    db ->
      config = %{
        "system_prompt" => params["system_prompt"] || "",
        "ranks" => parse_ranks(params["ranks"])
      }

      db
      |> ResourceDefinition.changeset(%{name: params["name"] || db.name, config: config})
      |> ExCalibur.Repo.update()
  end
end

defp parse_ranks(nil), do: %{}

defp parse_ranks(ranks_map) when is_map(ranks_map) do
  Map.new(ranks_map, fn {rank_key, v} ->
    {rank_key, %{"model" => v["model"] || "", "strategy" => v["strategy"] || "cot"}}
  end)
end

defp ranks_to_config(ranks) when is_map(ranks) do
  Map.new(ranks, fn {rank, data} ->
    {Atom.to_string(rank), %{"model" => data.model || "", "strategy" => data.strategy || "cot"}}
  end)
end
```

Remove the old private helpers: `list_roles/0`, `get_role/1`, `parse_perspectives/1`, `status_variant/1`.

**Step 4: Run tests**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul && mix test test/ex_calibur_web/live/members_live_test.exs 2>&1 | tail -40
```

Expected: all tests pass.

**Step 5: Compile and format**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul && mix compile --warnings-as-errors 2>&1 | tail -10 && mix format
```

Expected: no warnings.

**Step 6: Full test suite**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul && mix test 2>&1 | tail -20
```

Expected: all tests pass.

**Step 7: Commit**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul
git add lib/ex_calibur_web/live/members_live.ex test/ex_calibur_web/live/members_live_test.exs
git commit -m "feat: wire up member toggle, save, create, delete events"
```

---

## Task 4: Remove stale routes and clean up

**Files:**
- Modify: `lib/ex_calibur_web/router.ex`

The old `/members/new` and `/members/:id/edit` routes (`:new` and `:edit` live actions) are no longer used. Everything is inline now.

**Step 1: Find and check the routes**

```bash
grep -n "members" /home/andrew/projects/ex_calibur/.worktrees/members-overhaul/lib/ex_calibur_web/router.ex
```

**Step 2: Remove the :new and :edit live routes for members**

In `router.ex`, find the members routes block. It will look something like:

```elixir
live "/members", MembersLive, :index
live "/members/new", MembersLive, :new
live "/members/:id/edit", MembersLive, :edit
```

Remove the `:new` and `:edit` lines, keep only:

```elixir
live "/members", MembersLive, :index
```

**Step 3: Run full test suite**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul && mix test 2>&1 | tail -20
```

Expected: all tests pass.

**Step 4: Commit**

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul
git add lib/ex_calibur_web/router.ex
git commit -m "chore: remove stale /members/new and /members/:id/edit routes"
```

---

## Verification

After all tasks complete:

```bash
cd /home/andrew/projects/ex_calibur/.worktrees/members-overhaul
mix compile --warnings-as-errors && mix format --check-formatted && mix test
```

All three commands must succeed with zero warnings, zero format issues, zero test failures.
