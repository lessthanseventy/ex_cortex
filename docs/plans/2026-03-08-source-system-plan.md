# Source System Implementation Plan

**Design doc:** `docs/plans/2026-03-08-source-system-design.md`

---

## Task 1: Add dependencies (Req for HTTP, file_system for watching, websocket client)

**File:** `mix.exs`

**Steps:**
1. Add to deps:
   ```elixir
   {:req, "~> 0.5"},
   {:file_system, "~> 1.0"},
   {:fresh, "~> 0.4"},
   ```
   - `req` — HTTP client for FeedWatcher, UrlWatcher, GitWatcher (remote)
   - `file_system` — filesystem events for DirectoryWatcher
   - `fresh` — WebSocket client for WebSocketSource
2. Run `mix deps.get`

**Verify:** `mix deps.get && mix compile --warnings-as-errors`

---

## Task 2: Create sources migration and schema

**Files:**
- `priv/repo/migrations/20260308092633_add_sources.exs`
- `lib/ex_cellence_server/sources/source.ex`

**Steps:**
1. Create migration:
   ```elixir
   defmodule ExCellenceServer.Repo.Migrations.AddSources do
     use Ecto.Migration

     def change do
       create table(:excellence_sources, primary_key: false) do
         add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
         add :guild_name, :string, null: false
         add :source_type, :string, null: false
         add :config, :map, null: false, default: %{}
         add :state, :map, null: false, default: %{}
         add :status, :string, null: false, default: "active"
         add :last_run_at, :utc_datetime
         add :error_message, :string
         timestamps(type: :utc_datetime)
       end

       create index(:excellence_sources, [:guild_name])
       create index(:excellence_sources, [:status])
     end
   end
   ```
2. Create Source schema:
   ```elixir
   defmodule ExCellenceServer.Sources.Source do
     use Ecto.Schema
     import Ecto.Changeset

     @primary_key {:id, :binary_id, autogenerate: true}
     schema "excellence_sources" do
       field :guild_name, :string
       field :source_type, :string
       field :config, :map, default: %{}
       field :state, :map, default: %{}
       field :status, :string, default: "active"
       field :last_run_at, :utc_datetime
       field :error_message, :string
       timestamps(type: :utc_datetime)
     end

     def changeset(source, attrs) do
       source
       |> cast(attrs, [:guild_name, :source_type, :config, :state, :status, :last_run_at, :error_message])
       |> validate_required([:guild_name, :source_type])
       |> validate_inclusion(:source_type, ~w(git directory feed webhook url websocket))
       |> validate_inclusion(:status, ~w(active paused error))
     end
   end
   ```
3. Run migration: `mix ecto.migrate`

**Verify:** `mix compile --warnings-as-errors`

---

## Task 3: Create SourceItem struct and Source behaviour

**Files:**
- `lib/ex_cellence_server/sources/source_item.ex`
- `lib/ex_cellence_server/sources/behaviour.ex`

**Steps:**
1. Create SourceItem struct:
   ```elixir
   defmodule ExCellenceServer.Sources.SourceItem do
     defstruct [:source_id, :guild_name, :type, :content, :metadata]

     @type t :: %__MODULE__{
       source_id: String.t(),
       guild_name: String.t(),
       type: String.t(),
       content: String.t(),
       metadata: map()
     }
   end
   ```
2. Create behaviour:
   ```elixir
   defmodule ExCellenceServer.Sources.Behaviour do
     alias ExCellenceServer.Sources.SourceItem

     @callback init(config :: map()) :: {:ok, state :: map()} | {:error, term()}
     @callback fetch(state :: map(), config :: map()) :: {:ok, [SourceItem.t()], map()} | {:error, term()}
     @callback stop(state :: map()) :: :ok

     @optional_callbacks [stop: 1]
   end
   ```

**Verify:** `mix compile --warnings-as-errors`

---

## Task 4: Extract evaluation pipeline from EvaluateLive into shared module

**Files:**
- `lib/ex_cellence_server/evaluator.ex` (new)
- `lib/ex_cellence_server_web/live/evaluate_live.ex` (modify to use new module)

**Steps:**
1. Create `ExCellenceServer.Evaluator` module that extracts the reusable parts from EvaluateLive:
   ```elixir
   defmodule ExCellenceServer.Evaluator do
     alias Excellence.LLM.Ollama
     alias Excellence.Orchestrator

     @templates %{
       "Content Moderation" => Excellence.Templates.ContentModeration,
       "Code Review" => Excellence.Templates.CodeReview,
       "Risk Assessment" => Excellence.Templates.RiskAssessment
     }

     def templates, do: @templates

     def evaluate(guild_name, input_text, opts \\ []) do
       template_mod = Map.fetch!(@templates, guild_name)
       meta = template_mod.metadata()

       ollama_url = Application.get_env(:ex_cellence_server, :ollama_url, "http://127.0.0.1:11434")
       provider = Keyword.get(opts, :provider, Ollama.new(base_url: ollama_url))

       roles = build_roles_from_template(meta)
       actions_mod = build_actions_from_template(meta)

       Orchestrator.evaluate(
         %{subject: input_text},
         %{},
         roles: roles,
         actions: actions_mod,
         strategy: meta.strategy,
         llm_provider: provider,
         guards: []
       )
     end

     # Move build_roles_from_template/1 and build_actions_from_template/1 here
   end
   ```
2. Update EvaluateLive to delegate to `ExCellenceServer.Evaluator`:
   - Remove `build_roles_from_template/1` and `build_actions_from_template/1`
   - Update `run_evaluation/3` to call `ExCellenceServer.Evaluator.evaluate/2`
   - Keep `@templates` reference for UI display (use `Evaluator.templates()`)
3. Run existing evaluate test to confirm no regression

**Verify:** `mix compile --warnings-as-errors && mix test test/ex_cellence_server_web/live/evaluate_live_test.exs`

---

## Task 5: Create SourceWorker GenServer

**File:** `lib/ex_cellence_server/sources/source_worker.ex`

**Steps:**
1. Create the GenServer that drives poll-based sources:
   ```elixir
   defmodule ExCellenceServer.Sources.SourceWorker do
     use GenServer, restart: :transient
     require Logger

     alias ExCellenceServer.Sources.Source
     alias ExCellenceServer.Evaluator

     # Public API
     def start_link(%Source{} = source), do: GenServer.start_link(__MODULE__, source, name: via(source.id))
     defp via(id), do: {:via, Registry, {ExCellenceServer.SourceRegistry, id}}

     # Init: load source module, call init, schedule first fetch
     @impl true
     def init(%Source{} = source) do
       mod = source_module(source.source_type)
       case mod.init(source.config) do
         {:ok, worker_state} ->
           interval = get_in(source.config, ["interval"]) || 60_000
           timer = Process.send_after(self(), :fetch, interval)
           {:ok, %{source: source, mod: mod, worker_state: worker_state, timer: timer, interval: interval}}
         {:error, reason} ->
           {:stop, reason}
       end
     end

     # Fetch loop
     @impl true
     def handle_info(:fetch, state) do
       case state.mod.fetch(state.worker_state, state.source.config) do
         {:ok, items, new_worker_state} ->
           Enum.each(items, &evaluate_item/1)
           update_source_state(state.source, new_worker_state)
           timer = Process.send_after(self(), :fetch, state.interval)
           {:noreply, %{state | worker_state: new_worker_state, timer: timer}}
         {:error, reason} ->
           mark_source_error(state.source, reason)
           {:stop, :fetch_error, state}
       end
     end

     defp evaluate_item(item) do
       Task.Supervisor.start_child(ExCellenceServer.SourceTaskSupervisor, fn ->
         try do
           Evaluator.evaluate(item.guild_name, item.content)
         rescue
           e -> Logger.error("Source evaluation failed: #{inspect(e)}")
         end
       end)
     end

     defp source_module("git"), do: ExCellenceServer.Sources.GitWatcher
     defp source_module("directory"), do: ExCellenceServer.Sources.DirectoryWatcher
     defp source_module("feed"), do: ExCellenceServer.Sources.FeedWatcher
     defp source_module("url"), do: ExCellenceServer.Sources.UrlWatcher
     defp source_module("websocket"), do: ExCellenceServer.Sources.WebSocketSource

     defp update_source_state(source, new_state) do
       source
       |> Source.changeset(%{state: new_state, last_run_at: DateTime.utc_now(), status: "active", error_message: nil})
       |> ExCellenceServer.Repo.update()
     end

     defp mark_source_error(source, reason) do
       source
       |> Source.changeset(%{status: "error", error_message: inspect(reason)})
       |> ExCellenceServer.Repo.update()
     end
   end
   ```

**Verify:** `mix compile --warnings-as-errors`

---

## Task 6: Create SourceSupervisor and add to application tree

**Files:**
- `lib/ex_cellence_server/sources/source_supervisor.ex`
- `lib/ex_cellence_server/application.ex` (modify)

**Steps:**
1. Create SourceSupervisor:
   ```elixir
   defmodule ExCellenceServer.Sources.SourceSupervisor do
     use DynamicSupervisor

     alias ExCellenceServer.Sources.{Source, SourceWorker}

     def start_link(init_arg), do: DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)

     @impl true
     def init(_init_arg), do: DynamicSupervisor.init(strategy: :one_for_one)

     def start_source(%Source{} = source) do
       DynamicSupervisor.start_child(__MODULE__, {SourceWorker, source})
     end

     def stop_source(source_id) do
       case Registry.lookup(ExCellenceServer.SourceRegistry, source_id) do
         [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
         [] -> :ok
       end
     end

     def start_all_active do
       import Ecto.Query
       sources = ExCellenceServer.Repo.all(from s in Source, where: s.status == "active")
       Enum.each(sources, &start_source/1)
     end
   end
   ```
2. Add to application.ex children list (after Repo, before Endpoint):
   ```elixir
   {Registry, keys: :unique, name: ExCellenceServer.SourceRegistry},
   {Task.Supervisor, name: ExCellenceServer.SourceTaskSupervisor},
   ExCellenceServer.Sources.SourceSupervisor,
   ```
3. Add an `init/1` or post-boot hook to call `SourceSupervisor.start_all_active()`. Simplest: add a `handle_continue` or just call it in the supervisor's `init`. Better: use a simple GenServer or Task that runs after boot:
   ```elixir
   # Add to children list after SourceSupervisor:
   {Task, fn -> ExCellenceServer.Sources.SourceSupervisor.start_all_active() end},
   ```

**Verify:** `mix compile --warnings-as-errors && mix test`

---

## Task 7: Implement FeedWatcher source

**File:** `lib/ex_cellence_server/sources/feed_watcher.ex`

**Steps:**
1. Implement the behaviour — simplest source, good to build first:
   ```elixir
   defmodule ExCellenceServer.Sources.FeedWatcher do
     @behaviour ExCellenceServer.Sources.Behaviour
     alias ExCellenceServer.Sources.SourceItem

     @impl true
     def init(config) do
       {:ok, %{last_seen_ids: Map.get(config, "last_seen_ids", [])}}
     end

     @impl true
     def fetch(state, config) do
       url = config["url"]
       case Req.get(url) do
         {:ok, %{status: 200, body: body}} ->
           entries = parse_feed(body)
           new_entries = Enum.reject(entries, &(&1.id in state.last_seen_ids))
           items = Enum.map(new_entries, fn entry ->
             %SourceItem{
               source_id: config["source_id"],
               guild_name: config["guild_name"],
               type: "feed_entry",
               content: "#{entry.title}\n\n#{entry.description}",
               metadata: %{title: entry.title, link: entry.link, published_at: entry.published_at}
             }
           end)
           new_state = %{state | last_seen_ids: Enum.map(entries, & &1.id) |> Enum.take(100)}
           {:ok, items, new_state}
         {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
         {:error, reason} -> {:error, reason}
       end
     end

     # Simple RSS/Atom parser (extract items from XML)
     defp parse_feed(body) do
       # Parse XML, extract <item> or <entry> elements
       # Return list of %{id, title, description, link, published_at}
     end
   end
   ```
2. Implement `parse_feed/1` — use simple regex/string parsing for RSS 2.0 and Atom feeds. No need for a full XML parser dependency.

**Verify:** `mix compile --warnings-as-errors`

---

## Task 8: Implement GitWatcher source

**File:** `lib/ex_cellence_server/sources/git_watcher.ex`

**Steps:**
1. Implement the behaviour:
   - `init/1`: Store last known commit SHA from config/state
   - `fetch/2`: For local repos, run `git log` and `git diff` via `System.cmd`. For remote repos, `git ls-remote` to check for new commits, then fetch + diff.
   - Emit one SourceItem per new commit with the diff as content
   - Config keys: `repo_path`, `branch` (default "main"), `remote` (optional)
   - State: `last_sha`
2. Keep it simple — local repos only for v1. Shell out to `git`:
   ```elixir
   {output, 0} = System.cmd("git", ["log", "--oneline", "#{last_sha}..HEAD"], cd: repo_path)
   {diff, 0} = System.cmd("git", ["diff", "#{last_sha}..HEAD"], cd: repo_path)
   ```

**Verify:** `mix compile --warnings-as-errors`

---

## Task 9: Implement DirectoryWatcher source

**File:** `lib/ex_cellence_server/sources/directory_watcher.ex`

**Steps:**
1. Implement the behaviour:
   - `init/1`: Record initial file listing with modification times
   - `fetch/2`: Scan directory, compare mtimes with stored state, emit SourceItems for new/changed files
   - Config keys: `path`, `patterns` (default `["*"]`)
   - State: `file_mtimes` map of `%{path => mtime}`
2. Read file content for each changed file, emit as SourceItem
3. Note: We use polling here (not the `:file_system` library events) since it fits the SourceWorker fetch loop pattern. The `:file_system` dep is available if we want to optimize later.

**Verify:** `mix compile --warnings-as-errors`

---

## Task 10: Implement UrlWatcher source

**File:** `lib/ex_cellence_server/sources/url_watcher.ex`

**Steps:**
1. Implement the behaviour:
   - `init/1`: No initial state needed (or store last content hash)
   - `fetch/2`: `Req.get(url)`, compare body hash with previous, emit SourceItem if changed
   - Config keys: `url`, `css_selector` (optional, for future)
   - State: `last_hash`, `last_content`
2. Content diff: store previous body, emit the new body as content. Include a simple diff summary in metadata.

**Verify:** `mix compile --warnings-as-errors`

---

## Task 11: Implement WebhookReceiver (controller + route)

**Files:**
- `lib/ex_cellence_server_web/controllers/webhook_controller.ex`
- `lib/ex_cellence_server_web/router.ex` (modify)

**Steps:**
1. Create webhook controller:
   ```elixir
   defmodule ExCellenceServerWeb.WebhookController do
     use ExCellenceServerWeb, :controller

     alias ExCellenceServer.Sources.Source
     alias ExCellenceServer.Evaluator

     def receive(conn, %{"source_id" => source_id}) do
       import Ecto.Query

       with %Source{status: "active", source_type: "webhook"} = source <-
              ExCellenceServer.Repo.get(Source, source_id),
            true <- valid_token?(conn, source) do
         body = conn.body_params["content"] || Jason.encode!(conn.body_params)

         Task.Supervisor.start_child(ExCellenceServer.SourceTaskSupervisor, fn ->
           Evaluator.evaluate(source.guild_name, body)
         end)

         source |> Source.changeset(%{last_run_at: DateTime.utc_now()}) |> ExCellenceServer.Repo.update()
         json(conn, %{status: "accepted"})
       else
         nil -> conn |> put_status(404) |> json(%{error: "source not found"})
         false -> conn |> put_status(401) |> json(%{error: "unauthorized"})
       end
     end

     defp valid_token?(conn, source) do
       expected = get_in(source.config, ["auth_token"])
       if expected do
         case get_req_header(conn, "authorization") do
           ["Bearer " <> token] -> Plug.Crypto.secure_compare(token, expected)
           _ -> false
         end
       else
         true  # no token configured = open
       end
     end
   end
   ```
2. Add API route in router.ex:
   ```elixir
   scope "/api", ExCellenceServerWeb do
     pipe_through :api
     post "/webhooks/:source_id", WebhookController, :receive
   end
   ```
3. Add `:api` pipeline if not present:
   ```elixir
   pipeline :api do
     plug :accepts, ["json"]
   end
   ```

**Verify:** `mix compile --warnings-as-errors`

---

## Task 12: Implement WebSocketSource

**File:** `lib/ex_cellence_server/sources/websocket_source.ex`

**Steps:**
1. This source is different — it maintains a persistent connection rather than polling. Implement as a GenServer that doesn't use the standard SourceWorker fetch loop:
   ```elixir
   defmodule ExCellenceServer.Sources.WebSocketSource do
     @behaviour ExCellenceServer.Sources.Behaviour
     alias ExCellenceServer.Sources.SourceItem

     @impl true
     def init(config) do
       {:ok, %{message_path: config["message_path"]}}
     end

     @impl true
     def fetch(_state, _config) do
       # WebSocket sources don't poll — they push.
       # This is called by SourceWorker but returns empty.
       # The actual work happens in a custom GenServer.
       {:ok, [], %{}}
     end
   end
   ```
2. For v1, implement WebSocket as a SourceWorker override: the SourceWorker detects `source_type == "websocket"` and starts a Fresh WebSocket connection instead of the fetch loop. On each message, extract content via `message_path` (JSON path like `"data.content"`), build a SourceItem, and evaluate.
3. Alternative simpler approach: treat WebSocket as a poll source that connects, reads available messages, disconnects. Less efficient but fits the existing pattern. **Use this for v1.**

**Verify:** `mix compile --warnings-as-errors`

---

## Task 13: Create Sources LiveView page

**Files:**
- `lib/ex_cellence_server_web/live/sources_live.ex`
- `test/ex_cellence_server_web/live/sources_live_test.exs`
- `lib/ex_cellence_server_web/router.ex` (add route)
- `lib/ex_cellence_server_web/components/layouts/root.html.heex` (add nav link)

**Steps:**
1. Create SourcesLive:
   - `mount/3`: Load all sources from DB, subscribe to `"sources"` PubSub topic
   - Show table/cards of sources with: guild name, type, status, last_run_at, error_message
   - "Add Source" button opens a form with:
     - Guild picker (dropdown of installed guild names)
     - Source type picker (dropdown: git, directory, feed, webhook, url, websocket)
     - Dynamic config fields based on type:
       - git: repo_path, branch, interval
       - directory: path, patterns, interval
       - feed: url, interval
       - webhook: auth_token (auto-generated, show endpoint URL)
       - url: url, interval
       - websocket: url, message_path, reconnect_interval
   - Pause/Resume button: toggles status, stops/starts SourceWorker
   - Delete button: removes source row, stops worker
   - Status badge: green=active, yellow=paused, red=error (show error_message on hover)
2. Add route: `live "/sources", SourcesLive, :index`
3. Add nav link "Sources" between "Quests" and "Evaluate"
4. Create test asserting page renders

**Verify:** `mix compile --warnings-as-errors && mix test`

---

## Task 14: Integrate source creation into Guild Hall install flow

**File:** `lib/ex_cellence_server_web/live/guild_hall_live.ex`

**Steps:**
1. After `install_guild(mod)`, create a default source for the guild:
   ```elixir
   defp create_default_source(guild_name) do
     {source_type, default_config} = default_source_for(guild_name)

     %Source{}
     |> Source.changeset(%{
       guild_name: guild_name,
       source_type: source_type,
       config: default_config,
       status: "paused"  # start paused so user can configure first
     })
     |> ExCellenceServer.Repo.insert()
   end

   defp default_source_for("Code Review"), do: {"git", %{"repo_path" => "", "branch" => "main", "interval" => 60_000}}
   defp default_source_for("Content Moderation"), do: {"directory", %{"path" => "", "patterns" => ["*.txt", "*.md"], "interval" => 30_000}}
   defp default_source_for("Risk Assessment"), do: {"feed", %{"url" => "", "interval" => 300_000}}
   defp default_source_for(_), do: {"webhook", %{}}
   ```
2. Update `@post_install_redirect` to `"/sources"` so user lands on source config after install
3. For dissolve_and_install: also delete existing sources (`Repo.delete_all(from s in Source)`)

**Verify:** `mix compile --warnings-as-errors && mix test`

---

## Task 15: Update CLAUDE.md, run full verification, format

**Steps:**
1. Update CLAUDE.md:
   - Add Sources to pages list
   - Add source types documentation
   - Add new dependencies
2. Run `mix format`
3. Run `mix compile --warnings-as-errors`
4. Run `mix test`
5. Verify all passing

**Verify:** All commands pass cleanly.
