# Self-Improvement Loop Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** ExCortex operates on itself — a guild watches GitHub issues, writes code in worktrees, ships PRs, and gracefully restarts after merging.

**Architecture:** Issue-driven quest pipeline using existing reflect/escalate mechanics. New tools for file I/O and git ops. New GitHub issue source type. LearningLoop wired into step completion. Worktree isolation for all code changes.

**Tech Stack:** Elixir, Phoenix, Ecto, `gh` CLI, `git` CLI, ReqLLM tools, Ollama

**Design doc:** `docs/plans/2026-03-12-self-improvement-loop-design.md`

---

### Task 0: PID File on Boot

**Files:**
- Modify: `lib/ex_cortex/application.ex`

**Step 1: Write the PID file after supervision tree starts**

In `application.ex`, after the supervision tree starts successfully, write the beam OS PID to `.ex_cortex.pid`:

```elixir
# In start/2, after Supervisor.start_link:
result = Supervisor.start_link(children, opts)
check_cli_tools()
write_pid_file()
result
```

```elixir
defp write_pid_file do
  pid = System.pid()
  path = Path.join(File.cwd!(), ".ex_cortex.pid")
  File.write!(path, pid)
  Logger.info("PID file written: #{path} (#{pid})")
end
```

**Step 2: Add `.ex_cortex.pid` to `.gitignore`**

```
# Self-improvement loop
.ex_cortex.pid
.worktrees/
```

**Step 3: Verify**

Run: `mix compile`
Expected: compiles cleanly

**Step 4: Commit**

```bash
git add lib/ex_cortex/application.ex .gitignore
git commit -m "feat: write PID file on boot for graceful restart"
```

---

### Task 1: Restart Scripts

**Files:**
- Create: `bin/restart.sh`
- Create: `bin/restart-docker.sh`

**Step 1: Create `bin/restart.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PID_FILE="$PROJECT_DIR/.ex_cortex.pid"
PORT="${PORT:-4000}"
LOG_FILE="$PROJECT_DIR/log/restart.log"

mkdir -p "$(dirname "$LOG_FILE")"

echo "[restart] $(date -Iseconds) Starting restart..." | tee -a "$LOG_FILE"

# 1. Kill the beam
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    echo "[restart] Sending SIGTERM to PID $PID" | tee -a "$LOG_FILE"
    kill "$PID"

    # Wait up to 10s for graceful shutdown
    for i in $(seq 1 20); do
      if ! kill -0 "$PID" 2>/dev/null; then
        echo "[restart] Process exited after ${i}x500ms" | tee -a "$LOG_FILE"
        break
      fi
      sleep 0.5
    done

    # Force kill if still alive
    if kill -0 "$PID" 2>/dev/null; then
      echo "[restart] SIGKILL" | tee -a "$LOG_FILE"
      kill -9 "$PID"
      sleep 1
    fi
  fi
fi

# 2. Pull latest
cd "$PROJECT_DIR"
git pull --ff-only 2>&1 | tee -a "$LOG_FILE"

# 3. Install deps if mix.lock changed
if git diff HEAD~1 --name-only | grep -q "mix.lock"; then
  echo "[restart] mix.lock changed, running deps.get" | tee -a "$LOG_FILE"
  mix deps.get 2>&1 | tee -a "$LOG_FILE"
fi

# 4. Relaunch
echo "[restart] Launching mix phx.server..." | tee -a "$LOG_FILE"
nohup mix phx.server >> "$LOG_FILE" 2>&1 &

# 5. Wait for health
echo "[restart] Waiting for http://localhost:$PORT ..." | tee -a "$LOG_FILE"
for i in $(seq 1 60); do
  if curl -sf "http://localhost:$PORT" > /dev/null 2>&1; then
    echo "[restart] App is up after ${i}s" | tee -a "$LOG_FILE"
    exit 0
  fi
  sleep 1
done

echo "[restart] TIMEOUT — app did not come up in 60s" | tee -a "$LOG_FILE"
exit 1
```

**Step 2: Create `bin/restart-docker.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG_FILE="$PROJECT_DIR/log/restart.log"
PORT="${PORT:-4000}"

mkdir -p "$(dirname "$LOG_FILE")"

echo "[restart-docker] $(date -Iseconds) Starting restart..." | tee -a "$LOG_FILE"

cd "$PROJECT_DIR"
git pull --ff-only 2>&1 | tee -a "$LOG_FILE"

# Rebuild if deps changed
if git diff HEAD~1 --name-only | grep -q "mix.lock\|Dockerfile\|docker-compose"; then
  echo "[restart-docker] Rebuilding container..." | tee -a "$LOG_FILE"
  docker-compose up -d --build app 2>&1 | tee -a "$LOG_FILE"
else
  echo "[restart-docker] Restarting container..." | tee -a "$LOG_FILE"
  docker-compose restart app 2>&1 | tee -a "$LOG_FILE"
fi

# Wait for health
echo "[restart-docker] Waiting for http://localhost:$PORT ..." | tee -a "$LOG_FILE"
for i in $(seq 1 60); do
  if curl -sf "http://localhost:$PORT" > /dev/null 2>&1; then
    echo "[restart-docker] App is up after ${i}s" | tee -a "$LOG_FILE"
    exit 0
  fi
  sleep 1
done

echo "[restart-docker] TIMEOUT — app did not come up in 60s" | tee -a "$LOG_FILE"
exit 1
```

**Step 3: Make executable**

```bash
chmod +x bin/restart.sh bin/restart-docker.sh
```

**Step 4: Commit**

```bash
git add bin/restart.sh bin/restart-docker.sh
git commit -m "feat: add restart scripts for dev and docker modes"
```

---

### Task 2: New Tools — File I/O

**Files:**
- Create: `lib/ex_cortex/tools/read_file.ex`
- Create: `lib/ex_cortex/tools/write_file.ex`
- Create: `lib/ex_cortex/tools/edit_file.ex`
- Create: `lib/ex_cortex/tools/list_files.ex`
- Modify: `lib/ex_cortex/tools/registry.ex`
- Create: `test/ex_cortex/tools/file_tools_test.exs`

**Step 1: Write the test**

```elixir
defmodule ExCortex.Tools.FileToolsTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.EditFile
  alias ExCortex.Tools.ListFiles
  alias ExCortex.Tools.ReadFile
  alias ExCortex.Tools.WriteFile

  @tmp_dir System.tmp_dir!() |> Path.join("ex_cortex_tool_test")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  describe "ReadFile" do
    test "reads existing file" do
      path = Path.join(@tmp_dir, "hello.txt")
      File.write!(path, "hello world")
      assert {:ok, "hello world"} = ReadFile.call(%{"path" => path, "working_dir" => @tmp_dir})
    end

    test "rejects path traversal" do
      assert {:error, msg} = ReadFile.call(%{"path" => "../../../etc/passwd", "working_dir" => @tmp_dir})
      assert msg =~ "outside"
    end
  end

  describe "WriteFile" do
    test "writes new file" do
      path = Path.join(@tmp_dir, "new.txt")
      assert {:ok, _} = WriteFile.call(%{"path" => "new.txt", "content" => "hi", "working_dir" => @tmp_dir})
      assert File.read!(path) == "hi"
    end

    test "rejects path traversal" do
      assert {:error, _} = WriteFile.call(%{"path" => "../../escape.txt", "content" => "x", "working_dir" => @tmp_dir})
    end
  end

  describe "EditFile" do
    test "replaces text in file" do
      path = Path.join(@tmp_dir, "edit.txt")
      File.write!(path, "hello world")
      assert {:ok, _} = EditFile.call(%{"path" => "edit.txt", "old" => "world", "new" => "elixir", "working_dir" => @tmp_dir})
      assert File.read!(path) == "hello elixir"
    end

    test "errors when old text not found" do
      path = Path.join(@tmp_dir, "edit.txt")
      File.write!(path, "hello")
      assert {:error, _} = EditFile.call(%{"path" => "edit.txt", "old" => "missing", "new" => "x", "working_dir" => @tmp_dir})
    end
  end

  describe "ListFiles" do
    test "lists files matching pattern" do
      File.write!(Path.join(@tmp_dir, "a.ex"), "")
      File.write!(Path.join(@tmp_dir, "b.ex"), "")
      File.write!(Path.join(@tmp_dir, "c.txt"), "")
      assert {:ok, result} = ListFiles.call(%{"pattern" => "*.ex", "working_dir" => @tmp_dir})
      assert result =~ "a.ex"
      assert result =~ "b.ex"
      refute result =~ "c.txt"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/tools/file_tools_test.exs`
Expected: compilation errors (modules don't exist)

**Step 3: Implement ReadFile**

```elixir
defmodule ExCortex.Tools.ReadFile do
  @moduledoc "Tool: read a file from the working directory."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_file",
      description: "Read the contents of a file. Path is relative to the working directory.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Relative file path to read"}
        },
        "required" => ["path"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    full_path = Path.join(working_dir, path) |> Path.expand()

    if String.starts_with?(full_path, Path.expand(working_dir)) do
      case File.read(full_path) do
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:error, "Cannot read #{path}: #{reason}"}
      end
    else
      {:error, "Path #{path} is outside working directory"}
    end
  end
end
```

**Step 4: Implement WriteFile**

```elixir
defmodule ExCortex.Tools.WriteFile do
  @moduledoc "Tool: write content to a file in the working directory."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "write_file",
      description: "Write content to a file. Creates parent directories if needed. Path is relative to working directory.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Relative file path to write"},
          "content" => %{"type" => "string", "description" => "File content to write"}
        },
        "required" => ["path", "content"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path, "content" => content} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    full_path = Path.join(working_dir, path) |> Path.expand()

    if String.starts_with?(full_path, Path.expand(working_dir)) do
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, content)
      {:ok, "Wrote #{byte_size(content)} bytes to #{path}"}
    else
      {:error, "Path #{path} is outside working directory"}
    end
  end
end
```

**Step 5: Implement EditFile**

```elixir
defmodule ExCortex.Tools.EditFile do
  @moduledoc "Tool: find-and-replace text in a file."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "edit_file",
      description: "Replace a specific string in a file. The old string must appear exactly once.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Relative file path"},
          "old" => %{"type" => "string", "description" => "Exact text to find"},
          "new" => %{"type" => "string", "description" => "Replacement text"}
        },
        "required" => ["path", "old", "new"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path, "old" => old, "new" => new} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    full_path = Path.join(working_dir, path) |> Path.expand()

    if not String.starts_with?(full_path, Path.expand(working_dir)) do
      {:error, "Path #{path} is outside working directory"}
    else
      case File.read(full_path) do
        {:ok, content} ->
          case String.split(content, old) do
            [_before, _after] ->
              File.write!(full_path, String.replace(content, old, new, global: false))
              {:ok, "Replaced text in #{path}"}

            parts when length(parts) == 1 ->
              {:error, "Text not found in #{path}"}

            parts ->
              {:error, "Text appears #{length(parts) - 1} times in #{path} — must be unique"}
          end

        {:error, reason} ->
          {:error, "Cannot read #{path}: #{reason}"}
      end
    end
  end
end
```

**Step 6: Implement ListFiles**

```elixir
defmodule ExCortex.Tools.ListFiles do
  @moduledoc "Tool: list files matching a glob pattern."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "list_files",
      description: "List files matching a glob pattern in the working directory.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{"type" => "string", "description" => "Glob pattern (e.g. '**/*.ex', 'lib/**/*.ex')"},
          "path" => %{"type" => "string", "description" => "Subdirectory to search in (optional)"}
        },
        "required" => ["pattern"]
      },
      callback: &call/1
    )
  end

  def call(%{"pattern" => pattern} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    subdir = Map.get(params, "path", "")
    search_dir = Path.join(working_dir, subdir)

    files =
      Path.join(search_dir, pattern)
      |> Path.wildcard()
      |> Enum.map(&Path.relative_to(&1, working_dir))
      |> Enum.sort()
      |> Enum.take(100)

    {:ok, Enum.join(files, "\n")}
  end
end
```

**Step 7: Register tools in Registry**

Add to `registry.ex`:
- `ReadFile` and `ListFiles` to `@safe`
- `WriteFile` and `EditFile` to `@write`

**Step 8: Run tests**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/tools/file_tools_test.exs`
Expected: all pass

**Step 9: Commit**

```bash
git add lib/ex_cortex/tools/read_file.ex lib/ex_cortex/tools/write_file.ex \
  lib/ex_cortex/tools/edit_file.ex lib/ex_cortex/tools/list_files.ex \
  lib/ex_cortex/tools/registry.ex test/ex_cortex/tools/file_tools_test.exs
git commit -m "feat: add file I/O tools (read, write, edit, list)"
```

---

### Task 3: New Tools — Git Operations

**Files:**
- Create: `lib/ex_cortex/tools/git_commit.ex`
- Create: `lib/ex_cortex/tools/git_push.ex`
- Create: `lib/ex_cortex/tools/open_pr.ex`
- Create: `lib/ex_cortex/tools/merge_pr.ex`
- Create: `lib/ex_cortex/tools/git_pull.ex`
- Create: `lib/ex_cortex/tools/restart_app.ex`
- Create: `lib/ex_cortex/tools/close_issue.ex`
- Modify: `lib/ex_cortex/tools/registry.ex`
- Create: `test/ex_cortex/tools/git_tools_test.exs`

**Step 1: Write tests for git_commit (unit-testable parts)**

```elixir
defmodule ExCortex.Tools.GitToolsTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.GitCommit

  @tmp_dir System.tmp_dir!() |> Path.join("ex_cortex_git_test")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    System.cmd("git", ["init"], cd: @tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: @tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: @tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  test "git_commit stages files and commits" do
    File.write!(Path.join(@tmp_dir, "hello.ex"), "defmodule Hello, do: nil")

    assert {:ok, msg} =
             GitCommit.call(%{
               "files" => ["hello.ex"],
               "message" => "test commit",
               "working_dir" => @tmp_dir
             })

    assert msg =~ "Committed"
    {log, 0} = System.cmd("git", ["log", "--oneline"], cd: @tmp_dir)
    assert log =~ "test commit"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/tools/git_tools_test.exs`
Expected: compilation error

**Step 3: Implement GitCommit**

```elixir
defmodule ExCortex.Tools.GitCommit do
  @moduledoc "Tool: stage files and create a git commit in the working directory."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "git_commit",
      description: "Stage specific files and create a git commit.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "files" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Files to stage (relative paths)"
          },
          "message" => %{"type" => "string", "description" => "Commit message"}
        },
        "required" => ["files", "message"]
      },
      callback: &call/1
    )
  end

  def call(%{"files" => files, "message" => message} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())

    Enum.each(files, fn file ->
      System.cmd("git", ["add", file], cd: working_dir, stderr_to_stdout: true)
    end)

    case System.cmd("git", ["commit", "-m", message], cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Committed: #{output}"}
      {output, _} -> {:error, "Commit failed: #{output}"}
    end
  end
end
```

**Step 4: Implement GitPush**

```elixir
defmodule ExCortex.Tools.GitPush do
  @moduledoc "Tool: push a branch to origin."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "git_push",
      description: "Push the current branch to origin.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "branch" => %{"type" => "string", "description" => "Branch name to push"}
        },
        "required" => ["branch"]
      },
      callback: &call/1
    )
  end

  def call(%{"branch" => branch} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())

    case System.cmd("git", ["push", "-u", "origin", branch], cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Pushed #{branch}: #{output}"}
      {output, _} -> {:error, "Push failed: #{output}"}
    end
  end
end
```

**Step 5: Implement OpenPR**

```elixir
defmodule ExCortex.Tools.OpenPR do
  @moduledoc "Tool: open a GitHub pull request via gh CLI."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "open_pr",
      description: "Open a GitHub pull request from the current branch.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "title" => %{"type" => "string", "description" => "PR title"},
          "body" => %{"type" => "string", "description" => "PR description (markdown)"},
          "base" => %{"type" => "string", "description" => "Base branch (default: main)"}
        },
        "required" => ["title", "body"]
      },
      callback: &call/1
    )
  end

  def call(%{"title" => title, "body" => body} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    base = Map.get(params, "base", "main")

    args = ["pr", "create", "--title", title, "--body", body, "--base", base]

    case System.cmd("gh", args, cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "PR created: #{String.trim(output)}"}
      {output, _} -> {:error, "PR creation failed: #{output}"}
    end
  end
end
```

**Step 6: Implement MergePR**

```elixir
defmodule ExCortex.Tools.MergePR do
  @moduledoc "Tool: merge a GitHub pull request via gh CLI."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "merge_pr",
      description: "Merge a GitHub pull request by number.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "pr_number" => %{"type" => "integer", "description" => "PR number to merge"},
          "method" => %{"type" => "string", "description" => "Merge method: merge, squash, rebase (default: squash)"}
        },
        "required" => ["pr_number"]
      },
      callback: &call/1
    )
  end

  def call(%{"pr_number" => pr_number} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    method = Map.get(params, "method", "squash")

    args = ["pr", "merge", to_string(pr_number), "--#{method}", "--delete-branch"]

    case System.cmd("gh", args, cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "PR ##{pr_number} merged: #{output}"}
      {output, _} -> {:error, "Merge failed: #{output}"}
    end
  end
end
```

**Step 7: Implement GitPull**

```elixir
defmodule ExCortex.Tools.GitPull do
  @moduledoc "Tool: pull latest changes from origin."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "git_pull",
      description: "Pull latest changes from origin into the live copy. Fast-forward only.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{},
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())

    case System.cmd("git", ["pull", "--ff-only"], cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Pulled: #{output}"}
      {output, _} -> {:error, "Pull failed: #{output}"}
    end
  end
end
```

**Step 8: Implement RestartApp**

```elixir
defmodule ExCortex.Tools.RestartApp do
  @moduledoc "Tool: graceful restart of the ExCortex application."

  require Logger

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "restart_app",
      description: "Gracefully restart the ExCortex application after pulling new code.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "mode" => %{
            "type" => "string",
            "description" => "Restart mode: dev (default) or docker"
          }
        },
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(params) do
    mode = Map.get(params, "mode", "dev")
    project_dir = File.cwd!()

    script =
      case mode do
        "docker" -> Path.join(project_dir, "bin/restart-docker.sh")
        _ -> Path.join(project_dir, "bin/restart.sh")
      end

    Logger.info("[RestartApp] Triggering restart via #{script}")

    # Run the restart script as a detached process — it will kill us
    Port.open({:spawn_executable, script}, [:binary, args: [project_dir]])
    {:ok, "Restart initiated via #{script} — app will restart momentarily"}
  end
end
```

**Step 9: Implement CloseIssue**

```elixir
defmodule ExCortex.Tools.CloseIssue do
  @moduledoc "Tool: close a GitHub issue with a comment."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "close_issue",
      description: "Close a GitHub issue with an optional comment.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "issue_number" => %{"type" => "integer", "description" => "Issue number to close"},
          "comment" => %{"type" => "string", "description" => "Comment to add before closing"},
          "repo" => %{"type" => "string", "description" => "Repository in owner/repo format (optional)"}
        },
        "required" => ["issue_number"]
      },
      callback: &call/1
    )
  end

  def call(%{"issue_number" => issue_number} = params) do
    repo = Map.get(params, "repo") || ExCortex.Settings.get(:default_repo)

    unless repo do
      {:error, "repo required — pass 'repo' param or configure default_repo"}
    else
      comment = Map.get(params, "comment")

      if comment do
        System.cmd("gh", ["issue", "comment", to_string(issue_number), "--body", comment, "--repo", repo],
          stderr_to_stdout: true
        )
      end

      case System.cmd("gh", ["issue", "close", to_string(issue_number), "--repo", repo], stderr_to_stdout: true) do
        {output, 0} -> {:ok, "Issue ##{issue_number} closed: #{output}"}
        {output, _} -> {:error, "Close failed: #{output}"}
      end
    end
  end
end
```

**Step 10: Implement RunSandbox tool**

```elixir
defmodule ExCortex.Tools.RunSandbox do
  @moduledoc "Tool: run an allowlisted shell command in the working directory."

  @allowed_prefixes [
    "mix test",
    "mix credo",
    "mix dialyzer",
    "mix excessibility",
    "mix format",
    "mix deps.audit"
  ]

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "run_sandbox",
      description: "Run an allowlisted mix command in the working directory. Allowed: mix test, mix credo, mix dialyzer, mix excessibility, mix format, mix deps.audit.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "command" => %{"type" => "string", "description" => "Command to run (must be allowlisted)"}
        },
        "required" => ["command"]
      },
      callback: &call/1
    )
  end

  def call(%{"command" => command} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())

    if Enum.any?(@allowed_prefixes, &String.starts_with?(command, &1)) do
      case ExCortex.Sandbox.run(%{cmd: command, mode: :host}, working_dir) do
        {:ok, output, exit_code} -> {:ok, "Exit #{exit_code}:\n#{output}"}
        {:error, reason} -> {:error, "Sandbox error: #{inspect(reason)}"}
      end
    else
      {:error, "Command not allowed. Allowed: #{Enum.join(@allowed_prefixes, ", ")}"}
    end
  end
end
```

**Step 11: Register all new tools in Registry**

Add to `@write`: `GitCommit, GitPush, OpenPR`
Add to `@dangerous`: `MergePR, GitPull, RestartApp, CloseIssue`
Add to `@safe`: `RunSandbox`

**Step 12: Run tests**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/tools/git_tools_test.exs`
Expected: pass

**Step 13: Commit**

```bash
git add lib/ex_cortex/tools/git_commit.ex lib/ex_cortex/tools/git_push.ex \
  lib/ex_cortex/tools/open_pr.ex lib/ex_cortex/tools/merge_pr.ex \
  lib/ex_cortex/tools/git_pull.ex lib/ex_cortex/tools/restart_app.ex \
  lib/ex_cortex/tools/close_issue.ex lib/ex_cortex/tools/run_sandbox.ex \
  lib/ex_cortex/tools/registry.ex test/ex_cortex/tools/git_tools_test.exs
git commit -m "feat: add git and sandbox tools for self-improvement loop"
```

---

### Task 4: Worktree Manager

**Files:**
- Create: `lib/ex_cortex/worktree.ex`
- Create: `test/ex_cortex/worktree_test.exs`

**Step 1: Write the test**

```elixir
defmodule ExCortex.WorktreeTest do
  use ExUnit.Case, async: true

  alias ExCortex.Worktree

  @tmp_dir System.tmp_dir!() |> Path.join("ex_cortex_worktree_test")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    System.cmd("git", ["init"], cd: @tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: @tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: @tmp_dir)
    File.write!(Path.join(@tmp_dir, "README.md"), "hello")
    System.cmd("git", ["add", "."], cd: @tmp_dir)
    System.cmd("git", ["commit", "-m", "init"], cd: @tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    {:ok, repo: @tmp_dir}
  end

  test "creates and removes a worktree", %{repo: repo} do
    {:ok, path} = Worktree.create(repo, "42")
    assert File.exists?(path)
    assert File.exists?(Path.join(path, "README.md"))

    :ok = Worktree.remove(repo, "42")
    refute File.exists?(path)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/worktree_test.exs`

**Step 3: Implement**

```elixir
defmodule ExCortex.Worktree do
  @moduledoc "Manages git worktrees for isolated code changes."

  require Logger

  @worktree_dir ".worktrees"

  def create(repo_path, issue_id) do
    worktree_path = Path.join([repo_path, @worktree_dir, to_string(issue_id)])
    branch = "self-improve/#{issue_id}"

    File.mkdir_p!(Path.join(repo_path, @worktree_dir))

    case System.cmd("git", ["worktree", "add", worktree_path, "-b", branch],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Logger.info("[Worktree] Created #{worktree_path} on branch #{branch}")
        {:ok, worktree_path}

      {output, _} ->
        {:error, "Failed to create worktree: #{output}"}
    end
  end

  def remove(repo_path, issue_id) do
    worktree_path = Path.join([repo_path, @worktree_dir, to_string(issue_id)])
    branch = "self-improve/#{issue_id}"

    System.cmd("git", ["worktree", "remove", worktree_path, "--force"],
      cd: repo_path,
      stderr_to_stdout: true
    )

    System.cmd("git", ["branch", "-D", branch], cd: repo_path, stderr_to_stdout: true)
    Logger.info("[Worktree] Removed #{worktree_path}")
    :ok
  end

  def path(repo_path, issue_id) do
    Path.join([repo_path, @worktree_dir, to_string(issue_id)])
  end
end
```

**Step 4: Run tests**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/worktree_test.exs`
Expected: pass

**Step 5: Commit**

```bash
git add lib/ex_cortex/worktree.ex test/ex_cortex/worktree_test.exs
git commit -m "feat: add worktree manager for isolated code changes"
```

---

### Task 5: GitHub Issue Source

**Files:**
- Create: `lib/ex_cortex/sources/github_issue_watcher.ex`
- Modify: `lib/ex_cortex/sources/source_worker.ex` (add module mapping)
- Create: `test/ex_cortex/sources/github_issue_watcher_test.exs`

**Step 1: Write the test**

```elixir
defmodule ExCortex.Sources.GithubIssueWatcherTest do
  use ExUnit.Case, async: true

  alias ExCortex.Sources.GithubIssueWatcher

  test "init with valid config" do
    assert {:ok, %{seen_ids: []}} = GithubIssueWatcher.init(%{"repo" => "owner/repo", "label" => "self-improvement"})
  end

  test "init errors without repo" do
    assert {:error, _} = GithubIssueWatcher.init(%{})
  end
end
```

**Step 2: Run test to verify it fails**

**Step 3: Implement GithubIssueWatcher**

```elixir
defmodule ExCortex.Sources.GithubIssueWatcher do
  @moduledoc "Polls GitHub for issues with a specific label."
  @behaviour ExCortex.Sources.Behaviour

  alias ExCortex.Sources.SourceItem

  require Logger

  @impl true
  def init(config) do
    repo = config["repo"]

    if is_nil(repo) or repo == "" do
      {:error, "repo is required (owner/repo format)"}
    else
      {:ok, %{seen_ids: config["seen_ids"] || []}}
    end
  end

  @impl true
  def fetch(state, config) do
    repo = config["repo"]
    label = config["label"] || "self-improvement"

    args = [
      "issue", "list",
      "--repo", repo,
      "--label", label,
      "--state", "open",
      "--json", "number,title,body,labels,createdAt",
      "--limit", "10"
    ]

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} ->
        issues = Jason.decode!(output)
        new_issues = Enum.reject(issues, &(&1["number"] in state.seen_ids))

        items =
          Enum.map(new_issues, fn issue ->
            %SourceItem{
              source_id: config["source_id"],
              type: "github_issue",
              content: "## Issue ##{issue["number"]}: #{issue["title"]}\n\n#{issue["body"]}",
              metadata: %{
                number: issue["number"],
                title: issue["title"],
                labels: Enum.map(issue["labels"] || [], & &1["name"])
              }
            }
          end)

        new_seen = state.seen_ids ++ Enum.map(new_issues, & &1["number"])
        {:ok, items, %{state | seen_ids: new_seen}}

      {error, _} ->
        Logger.warning("[GithubIssueWatcher] gh command failed: #{error}")
        {:error, error}
    end
  end
end
```

**Step 4: Register in SourceWorker**

Add to `source_module/1` in `source_worker.ex`:

```elixir
defp source_module("github_issues"), do: ExCortex.Sources.GithubIssueWatcher
```

**Step 5: Run tests**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/sources/github_issue_watcher_test.exs`

**Step 6: Commit**

```bash
git add lib/ex_cortex/sources/github_issue_watcher.ex \
  lib/ex_cortex/sources/source_worker.ex \
  test/ex_cortex/sources/github_issue_watcher_test.exs
git commit -m "feat: add GitHub issue watcher source type"
```

---

### Task 6: Wire LearningLoop into Step Completion

**Files:**
- Modify: `lib/ex_cortex/quest_runner.ex`
- Create: `test/ex_cortex/learning_loop_test.exs`

**Step 1: Write a test that LearningLoop.retrospect is called**

```elixir
defmodule ExCortex.LearningLoopTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.LearningLoop

  test "retrospect returns empty list when Claude not configured" do
    step = %ExCortex.Quests.Step{id: 1, name: "test", trigger: "manual", roster: []}
    step_run = %{id: 1, results: %{}, input: "test input"}
    assert {:ok, []} = LearningLoop.retrospect(step, step_run)
  end
end
```

**Step 2: Wire retrospect call into QuestRunner**

In `quest_runner.ex`, after a step completes successfully, call `LearningLoop.retrospect/2` asynchronously:

```elixir
# After StepRunner.run returns, in the step execution block:
Task.Supervisor.start_child(ExCortex.AsyncTaskSupervisor, fn ->
  case resolve_step(step_id) do
    nil -> :ok
    resolved_step ->
      step_run = %{id: quest_run.id, results: inspect_result(result), input: current_input}
      LearningLoop.retrospect(resolved_step, step_run)
  end
end)
```

**Step 3: Run tests**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/learning_loop_test.exs`

**Step 4: Commit**

```bash
git add lib/ex_cortex/quest_runner.ex test/ex_cortex/learning_loop_test.exs
git commit -m "feat: wire LearningLoop.retrospect into quest step completion"
```

---

### Task 7: Expand Dangerous Tools and Worktree Context

**Files:**
- Modify: `lib/ex_cortex/step_runner.ex`

**Step 1: Expand dangerous tools list**

In `step_runner.ex`, update `@dangerous_tools`:

```elixir
@dangerous_tools ~w(send_email create_github_issue comment_github run_quest merge_pr git_pull restart_app close_issue)
```

**Step 2: Add worktree context injection**

The `working_dir` needs to be injected into tool params when tools are called within a quest that has worktree context. This is passed through the quest context from the source trigger.

Modify `resolve_member_tools/1` to accept and bind a `working_dir`:

```elixir
defp resolve_member_tools(names, working_dir) when is_list(names) do
  ExCortex.Tools.Registry.resolve_tools(names)
  |> Enum.map(fn tool ->
    if working_dir do
      %{tool | callback: fn params -> tool.callback.(Map.put(params, "working_dir", working_dir)) end}
    else
      tool
    end
  end)
end
```

**Step 3: Run full test suite**

Run: `cd /home/andrew/projects/ex_cortex && mix test`

**Step 4: Commit**

```bash
git add lib/ex_cortex/step_runner.ex
git commit -m "feat: expand dangerous tools list and add worktree context injection"
```

---

### Task 8: Dev Team Charter

**Files:**
- Create: `lib/ex_cortex/charters/dev_team.ex`
- Modify: `lib/ex_cortex/evaluator.ex` (register charter)
- Create: `test/ex_cortex/charters/dev_team_test.exs`

This task creates the charter definition that the guild installs from. The charter defines the 6 members (PM, Product Analyst, Code Writer, Code Reviewer, QA/Test Writer, UX Designer) with their system prompts, tool assignments, and model configs.

**Step 1: Study existing charter pattern**

Read an existing charter in the `ex_cellence` dependency to understand the exact module structure (metadata/0, roles, etc.).

Run: `find /home/andrew/projects/ex_cellence/lib -name "*.ex" -path "*/charters/*" | head -3`
Then read one to get the pattern.

**Step 2: Implement the Dev Team charter**

The charter should define metadata and roles matching the design doc. Each member gets:
- A system prompt explaining their role in the self-improvement loop
- Tool assignments matching the design doc member-tool mapping
- Default model (Ollama) with configurable override

**Step 3: Register in Evaluator**

Add to `@charters` map in `evaluator.ex`:

```elixir
"Dev Team" => ExCortex.Charters.DevTeam,
```

**Step 4: Write test verifying charter metadata**

```elixir
defmodule ExCortex.Charters.DevTeamTest do
  use ExUnit.Case, async: true

  alias ExCortex.Charters.DevTeam

  test "metadata returns expected members" do
    meta = DevTeam.metadata()
    names = Enum.map(meta.roles, & &1.name)
    assert "Project Manager" in names
    assert "Product Analyst" in names
    assert "Code Writer" in names
    assert "Code Reviewer" in names
    assert "QA / Test Writer" in names
    assert "UX Designer" in names
  end
end
```

**Step 5: Run tests**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/charters/dev_team_test.exs`

**Step 6: Commit**

```bash
git add lib/ex_cortex/charters/dev_team.ex lib/ex_cortex/evaluator.ex \
  test/ex_cortex/charters/dev_team_test.exs
git commit -m "feat: add Dev Team charter for self-improvement guild"
```

---

### Task 9: Self-Improvement Quest Seed

**Files:**
- Create: `lib/ex_cortex/self_improvement/quest_seed.ex`

This module creates the quest, steps, and source records needed for the self-improvement cycle when the Dev Team charter is installed. Called from the guild installation flow.

**Step 1: Implement the seed module**

Creates:
1. A `github_issues` source watching for `self-improvement` label
2. 6 steps matching the pipeline (PM triage, Code Writer, Code Reviewer, QA, UX, PM merge)
3. A quest linking the steps in order, triggered by the source
4. A scheduled quest for the Product Analyst sweep (daily)

Each step has:
- Correct `output_type` (freeform for most, verdict for reviewers)
- Correct `loop_mode` / `reflect` settings for Code Writer and QA
- Correct `escalate` settings for PM merge decision
- Tool assignments via member config

**Step 2: Write test**

```elixir
defmodule ExCortex.SelfImprovement.QuestSeedTest do
  use ExCortex.DataCase

  alias ExCortex.SelfImprovement.QuestSeed

  test "seed creates quest, steps, and source" do
    {:ok, result} = QuestSeed.seed(%{repo: "owner/repo"})
    assert result.quest
    assert length(result.steps) == 6
    assert result.source
    assert result.sweep_quest
  end
end
```

**Step 3: Run tests, implement, run tests again**

**Step 4: Commit**

```bash
git add lib/ex_cortex/self_improvement/quest_seed.ex \
  test/ex_cortex/self_improvement/quest_seed_test.exs
git commit -m "feat: add quest seed for self-improvement pipeline"
```

---

### Task 10: GitHub Issue Book

**Files:**
- Modify: `lib/ex_cortex/sources/book.ex`

**Step 1: Add a book entry for the GitHub issue watcher**

Add to the book catalog in `book.ex`:

```elixir
%Book{
  id: "github_issue_watcher",
  name: "GitHub Issue Watcher",
  description: "Watches a GitHub repository for issues with a specific label. Use with the self-improvement guild to automatically pick up and work issues.",
  source_type: "github_issues",
  icon: "github",
  config_schema: %{
    "repo" => %{"type" => "string", "required" => true, "description" => "Repository (owner/repo)"},
    "label" => %{"type" => "string", "default" => "self-improvement", "description" => "Issue label to watch"},
    "interval" => %{"type" => "integer", "default" => 300_000, "description" => "Poll interval in ms (default 5min)"}
  }
}
```

**Step 2: Commit**

```bash
git add lib/ex_cortex/sources/book.ex
git commit -m "feat: add GitHub Issue Watcher book to Library"
```

---

### Task 11: Boot-Time Restart Confirmation

**Files:**
- Modify: `lib/ex_cortex/application.ex`

**Step 1: Add restart confirmation check on boot**

After the supervision tree starts, check for quest runs that were in "restarting" status and update them:

```elixir
defp check_restart_status do
  import Ecto.Query

  case ExCortex.Repo.all(
         from(qr in ExCortex.Quests.QuestRun,
           where: qr.status == "restarting",
           preload: [:quest]
         )
       ) do
    [] ->
      :ok

    runs ->
      Enum.each(runs, fn run ->
        Logger.info("[Boot] Confirming restart for quest run #{run.id} (#{run.quest.name})")
        ExCortex.Quests.update_quest_run(run, %{status: "complete"})
      end)
  end
rescue
  _ -> :ok
end
```

**Step 2: Call from `start/2`**

```elixir
result = Supervisor.start_link(children, opts)
check_cli_tools()
write_pid_file()
check_restart_status()
result
```

**Step 3: Commit**

```bash
git add lib/ex_cortex/application.ex
git commit -m "feat: confirm pending restart quest runs on boot"
```

---

### Task 12: Integration Test — Full Loop

**Files:**
- Create: `test/ex_cortex/integration/self_improvement_test.exs`

**Step 1: Write an integration test**

Test the flow: source creates item → quest runner processes steps → worktree created → files modified → commit made → worktree cleaned up.

This test uses a local git repo (no actual GitHub API calls) to verify the mechanical flow works end-to-end. Mock `gh` commands or skip PR/merge steps.

```elixir
defmodule ExCortex.Integration.SelfImprovementTest do
  use ExCortex.DataCase

  alias ExCortex.Worktree

  @tmp_dir System.tmp_dir!() |> Path.join("self_improve_integration")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    System.cmd("git", ["init"], cd: @tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: @tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: @tmp_dir)
    File.write!(Path.join(@tmp_dir, "lib/hello.ex"), "defmodule Hello, do: nil")
    System.cmd("git", ["add", "."], cd: @tmp_dir)
    System.cmd("git", ["commit", "-m", "init"], cd: @tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    {:ok, repo: @tmp_dir}
  end

  test "worktree lifecycle: create, modify, commit, cleanup", %{repo: repo} do
    {:ok, wt_path} = Worktree.create(repo, "test-42")
    assert File.exists?(wt_path)

    # Simulate Code Writer modifying a file
    File.write!(Path.join(wt_path, "lib/hello.ex"), "defmodule Hello do\n  def greet, do: :hi\nend")
    {_, 0} = System.cmd("git", ["add", "lib/hello.ex"], cd: wt_path)
    {_, 0} = System.cmd("git", ["commit", "-m", "feat: add greet function"], cd: wt_path)

    # Verify commit exists on the branch
    {log, 0} = System.cmd("git", ["log", "--oneline", "self-improve/test-42"], cd: repo)
    assert log =~ "add greet function"

    # Cleanup
    :ok = Worktree.remove(repo, "test-42")
    refute File.exists?(wt_path)
  end
end
```

**Step 2: Run integration test**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/integration/self_improvement_test.exs`

**Step 3: Commit**

```bash
git add test/ex_cortex/integration/self_improvement_test.exs
git commit -m "test: add integration test for self-improvement worktree lifecycle"
```

---

### Task 13: Compile & Full Test Suite

**Step 1: Run full compilation**

Run: `cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors`

**Step 2: Run full test suite**

Run: `cd /home/andrew/projects/ex_cortex && mix test`

**Step 3: Fix any failures**

**Step 4: Run formatter**

Run: `cd /home/andrew/projects/ex_cortex && mix format`

**Step 5: Final commit**

```bash
git add -A
git commit -m "chore: format and fix warnings after self-improvement loop implementation"
```
