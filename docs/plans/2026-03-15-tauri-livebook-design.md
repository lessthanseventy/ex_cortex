# Tauri Desktop App + Livebook Integration — Design Sketch

> **Status:** Rough sketch for future session. Needs brainstorming.

**Goal:** ExCortex as a native desktop app (Tauri) with embedded Livebook for interactive data exploration.

---

## Tauri Wrapper

Tauri wraps the Phoenix web UI in a native window. The Burrito binary runs as a sidecar process.

**How it works:**
1. Tauri app launches
2. Starts the ExCortex Burrito binary as a sidecar process
3. Waits for the web server to be ready (poll `http://localhost:4001/`)
4. Opens a webview pointing at `http://localhost:4001`
5. System tray icon for background operation

**What you get:**
- Native app feel (cmd+Q, dock icon, system tray)
- No "open your browser" — it IS the app
- Auto-start on login (optional)
- Menu bar with quick actions (new musing, open cortex, etc.)
- Notifications via native OS notifications instead of browser

**Structure:**
```
tauri/
  src-tauri/
    src/main.rs          # Tauri entry point, sidecar management
    tauri.conf.json       # Window config, sidecar registration
    icons/                # App icons
  src/
    index.html            # Just loads the Phoenix app in webview
```

**Key decisions to make:**
- Do we embed the Burrito binary inside the Tauri .app bundle? (yes, probably)
- Do we also bundle Postgres? (SQLite alternative? Or require Postgres externally?)
- Tauri v2 has mobile support — do we want iOS/Android eventually?

---

## Livebook Integration

Livebook is an interactive notebook for Elixir. Integration options:

### Option A: Embedded Livebook (recommended)

Add `livebook` as a dependency. Start it as part of the OTP application on a separate port (e.g., 4002). Pre-configure it to connect to the running ExCortex node.

```elixir
# In application.ex supervision tree
{Livebook, port: 4002, token: auto_generated}
```

Users get:
- A "Notebook" nav link that opens Livebook at `:4002`
- Pre-built notebook templates for common tasks ("Analyze my engrams", "Query axioms", "Build a rumination")
- Full access to ExCortex modules — `ExCortex.Memory.query("elixir")`, `ExCortex.Muse.ask("...")`, etc.
- Notebook results can be saved as engrams

### Option B: Livebook as Attached Node

Run Livebook separately but attach it to the ExCortex BEAM node. Less integrated but simpler to maintain.

### Option C: Livebook-style Notebooks in ExCortex

Build our own notebook UI inside ExCortex (LiveView). More work but fully integrated. Probably overkill when Livebook already exists.

**Recommendation:** Option A. Embed Livebook, ship pre-built notebooks, add a nav link.

---

## Brain Vocabulary Extension

- **Notebook** → already fits the brain metaphor (a place to think through things)
- The Tauri app could be called the **Skull** — the container that holds the brain
- Or just **ExCortex.app** — keep it simple

---

## Open Questions

1. SQLite vs Postgres for desktop? Postgres is a hard dependency right now. For a desktop app, requiring a running Postgres is friction. Could we support SQLite for single-user desktop mode?
2. Bundling Ollama? Tauri could also manage an Ollama sidecar. Then the app is fully self-contained — no external dependencies at all.
3. How does Tauri interact with the TUI? Do we drop the TUI in favor of the Tauri native app? Or keep both as options?
4. Livebook auth — embedded Livebook needs to be secured (token auth, only accessible from localhost)
