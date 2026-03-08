# Sandbox Execution Design

## Problem

Guild members currently only evaluate text input. Real-world review tasks require running actual tools — an a11y reviewer needs excessibility, a dependency auditor needs mix audit, a performance auditor needs benchmarks. Without tool execution, members can only reason about code, not test it.

## Design

### Where it lives

Sandbox is a **source-level concern**. Books in the library get an optional `sandbox` field. When a source worker fetches a change, if the book has a sandbox spec, it runs the tool first and wraps both the source content and tool output into a structured envelope for members to evaluate.

Members don't know about sandboxes. They just get richer input.

### Execution modes

Two modes, configurable per book:

**Host mode (default):** Runs in a separate OS process using the local mise/asdf environment. Respects the developer's existing toolchain. Applied when no `image` is specified.

```elixir
sandbox: %{cmd: "mix excessibility", timeout: 120_000}
```

**Container mode:** Full Podman isolation. Use registry images or pre-built project-specific images.

```elixir
sandbox: %{
  mode: :container,
  image: "elixir:1.17",
  setup: "mix deps.get",
  cmd: "mix excessibility",
  timeout: 120_000
}
```

Container mode protects the Excellence runtime from rogue tools. Host mode is simpler and faster for trusted local tooling.

### Container images

- Pull from registry at runtime by default (Docker Hub, etc.)
- Support custom pre-built images for faster cold starts
- `setup` field handles first-run initialization (deps.get, compile, etc.)

### Source worker flow

Existing flow: source watcher detects change -> fetches content -> sends to evaluator.

New flow: source watcher detects change -> fetches content -> **if sandbox configured, runs tool** -> wraps output -> sends to evaluator.

### Output format

Tool output is wrapped in a structured envelope so members can distinguish source material from tool results:

```
## Source Content
<the git diff, file contents, or feed entry>

## Tool Output (mix excessibility)
<stdout/stderr from the sandbox run>
```

Members with relevant expertise (a11y reviewer) focus on the tool output section. Members without tool awareness (grammar editor) focus on source content. System prompts already direct each member's attention.

### Book example

```elixir
%Book{
  id: "excessibility-scanner",
  name: "Excessibility Scanner",
  kind: :book,
  source_type: "directory",
  description: "Runs excessibility a11y checks against a Phoenix project.",
  suggested_guild: "Accessibility Review",
  sandbox: %{
    cmd: "mix excessibility",
    timeout: 120_000
  },
  default_config: %{"path" => ""}
}
```

### Data model changes

- Add `sandbox` map field to Book struct (optional, default nil)
- No schema migration needed — Book is an in-memory catalogue, not a DB table
- Source worker checks `book.sandbox` before evaluation

### Implementation scope

1. `Sandbox` module — executes commands in host or container mode, captures stdout/stderr, enforces timeout
2. `Sandbox.Host` — runs via `System.cmd/3` with cwd set to source path
3. `Sandbox.Container` — runs via `podman run` with volume mounts
4. Update `SourceWorker` to check for sandbox config and run before evaluation
5. Update `Book` struct to include optional `sandbox` field
6. Add sandbox books to the library catalogue (excessibility, credo, mix audit, dialyzer, etc.)
7. Wrap source content + tool output in structured envelope format
