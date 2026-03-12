# Self-Improvement Loop Design

ExCalibur operates on itself: a guild of AI members watches its own GitHub issues,
writes code, reviews it, tests it, and ships PRs — with the human owner as CTO
receiving escalations.

## Guild: "ExCalibur Dev Team"

### Members (v1)

| Member | Discipline | Reflect? | Escalate? |
|--------|-----------|----------|-----------|
| Project Manager | Triage, prioritization, merge decisions | No | Yes → CTO (lodge proposal) |
| Product Analyst | Usage analysis, pain points, ticket creation | No | Yes → PM |
| Code Writer | Elixir, Phoenix, LiveView | Yes (retry until tests pass) | Yes → PM |
| Code Reviewer | Code quality, patterns, security | No | Yes → PM (request changes) |
| QA / Test Writer | Testing, coverage | Yes (retry until passing) | Yes → PM |
| UX Designer | Accessibility, UI patterns | No | Yes → PM |

### Members (v2, deferred)

- Architect — structural changes, dependency impacts

### Tool Assignment

**Safe tools (no proposal needed):**
- `read_file` — read file from worktree, sandboxed to repo dir
- `list_files` — glob files in worktree
- `run_sandbox` — run allowlisted shell command in worktree, capture output

**Write tools (auto-approved within quest context):**
- `write_file` — write/overwrite file in worktree
- `edit_file` — find-and-replace in worktree file
- `git_commit` — stage specific files and commit in worktree
- `git_push` — push worktree branch to origin
- `open_pr` — open GitHub PR via API

**Dangerous tools (require PM decision or lodge escalation):**
- `merge_pr` — merge PR via GitHub API
- `git_pull` — pull latest main into live running instance
- `restart_app` — graceful restart (dev or docker mode)
- `close_issue` — close GitHub issue with comment

**Sandbox command allowlist:**
- `mix test`, `mix test <path>`
- `mix credo --strict`
- `mix dialyzer`
- `mix excessibility`
- `mix format --check-formatted`, `mix format`
- `mix deps.audit`

### Member-Tool Mapping

- **PM:** `search_github`, `comment_github`, `merge_pr`, `git_pull`, `restart_app`, `close_issue`
- **Product Analyst:** `read_obsidian`, `query_lore`, `search_github`, `create_github_issue`, `read_file`, `list_files`, `run_sandbox`
- **Code Writer:** `read_file`, `list_files`, `write_file`, `edit_file`, `git_commit`, `git_push`, `open_pr`, `run_sandbox`
- **Code Reviewer:** `read_file`, `list_files`, `search_github`, `comment_github`
- **QA / Test Writer:** `read_file`, `list_files`, `write_file`, `edit_file`, `run_sandbox`, `comment_github`
- **UX Designer:** `read_file`, `list_files`, `run_sandbox` (excessibility for context, not gating), `comment_github`

## Quest Pipeline: "Self-Improvement Cycle"

Triggered by GitHub issues with the `self-improvement` label.

```
Issue filed (label: self-improvement)
  │
  ▼
Step 1: PM — Triage & Plan
  │  Reads issue, checks priority, writes implementation plan
  │  Can reject (close issue with comment) or proceed
  │  Output: plan document → feeds Step 2
  │
  ▼
Step 2: Code Writer — Implement
  │  Receives plan, reads relevant files, writes code in worktree
  │  Reflect mode: runs tests via sandbox, iterates until passing
  │  Output: git commit on branch, PR opened → feeds Step 3
  │
  ▼
Step 3: Code Reviewer — Review
  │  Reads PR diff, checks against plan, checks patterns
  │  Can: approve, request changes (escalate → PM files new issue), or block
  │  Output: review verdict → feeds Step 4
  │
  ▼
Step 4: QA / Test Writer — Verify
  │  Runs full test suite via sandbox
  │  Runs mix credo, mix dialyzer
  │  Reflect mode: if tests are insufficient, writes more
  │  Output: test verdict → feeds Step 5
  │
  ▼
Step 5: UX Designer — Accessibility Check
  │  Runs mix excessibility via sandbox (context, not gating)
  │  Reviews any LiveView template changes
  │  Output: UX verdict → feeds Step 6
  │
  ▼
Step 6: PM — Merge Decision
  │  Reviews all verdicts from steps 3-5
  │  Auto-merge if: all pass + change is low-risk
  │  Escalate to CTO (lodge proposal) if: core logic, new features, deps
  │  On merge: git pull + graceful restart
```

## Worktree Strategy

The guild works in isolated git worktrees, not the live running copy.

- On issue pickup: `git worktree add .worktrees/<issue-number> -b self-improve/<issue-number>`
- All file operations sandboxed to worktree path
- Worktree path passed through quest context to every step
- After PR merged or rejected: `git worktree remove .worktrees/<issue-number>`
- Multiple issues could be worked concurrently in future

## Graceful Restart

### Dev mode

A `bin/restart.sh` script:
1. Reads beam PID from `.ex_calibur.pid` (written on app boot)
2. Sends SIGTERM to beam process
3. Polls for process exit (timeout 10s)
4. SIGKILL if it won't die
5. Relaunches `mix phx.server`, writes new PID
6. Polls `http://localhost:4000` until healthy (timeout 30s)

### Docker mode

A `bin/restart-docker.sh` script:
1. `docker-compose restart app` (or `docker-compose up -d --build app` if deps changed)
2. Polls health endpoint until ready

### Safety

- Restart is the very last action in the quest
- Quest runner saves completion status to DB before triggering restart
- On boot, app checks for "completed but not yet confirmed" quests and logs outcome
- If new code crashes on boot (app doesn't come up within 30s):
  - Run `git revert HEAD` on live copy
  - Restart again
  - File new issue: "Revert: {original issue title} — boot failure"

### PID file

App writes its PID to `.ex_calibur.pid` on boot. Restart script reads it.

## Feedback Loop

The guild files issues against itself, making the loop self-sustaining.

### Sources of new issues

| Source | Trigger | Example |
|--------|---------|---------|
| Code Reviewer | Spots problems beyond current PR scope | "Inconsistent error handling in Sandbox module" |
| QA | Test run reveals existing gaps | "No tests for QuestDebouncer timeout edge case" |
| UX Designer | Excessibility output reveals pre-existing violations | "Lodge page missing aria labels on proposal cards" |
| PM — post-merge | Reflects on quest execution | "Code Writer didn't check for existing tests first" |
| Product Analyst — scheduled sweep | Reads obsidian notes, lore, lodge history, git churn | "User keeps editing lodge_live.ex — investigate UX friction" |
| Product Analyst — ad hoc | Spots user-facing issues during quest context | "Evaluation page has no loading state, user probably stares at a blank screen" |

### Scheduled Sweep

A separate quest triggered on a schedule (configurable, default daily). The **Product Analyst**:

1. Gathers user context:
   - Reads recent Obsidian notes via `read_obsidian` — look for frustrations, TODOs, wishes
   - Queries Lore for evaluation patterns — what runs most, what fails, what gets rejected
   - Checks Lodge card history — which proposals got approved vs rejected (signals user preferences)
   - Reviews recent git history — what the user changes most often (churn = pain points)
2. Gathers code context:
   - `git log --shortstat` for frequently changed files
   - `git log --diff-filter=A` for newly added files that may lack tests
   - `run_sandbox` for credo/dialyzer output
3. Cross-references user signals with code signals:
   - User mentions "lodge is slow" + lodge_live.ex has high churn = high-priority issue
   - User writes obsidian note about a workflow + no tests for that workflow = file ticket
4. Files `self-improvement` issues prioritized by user impact, not just code quality
5. Rate limit: max 3 issues per sweep

The PM then triages these alongside any other open issues.

This ensures the backlog reflects what the user actually cares about, not just
what a linter found.

### Issue format

All self-filed issues use the `self-improvement` label and structured body:

```markdown
## Source
Filed by: {member name} during quest #{quest_id}

## Context
{what triggered this observation}

## Proposed Change
{what should be done}

## Risk Level
{low/medium/high — informs PM auto-merge vs escalate decision}
```

### Wire-up

- Activate dormant `LearningLoop.retrospect/2` after step completion
- Proposals of type `"other"` converted to GitHub issues by PM
- Rate limit: PM files at most 3 issues per quest run

## Infrastructure Changes Summary

### New modules
- Charter definition for "ExCalibur Dev Team" guild
- Tool implementations: `read_file`, `list_files`, `write_file`, `edit_file`, `git_commit`, `git_push`, `open_pr`, `merge_pr`, `git_pull`, `restart_app`, `close_issue`, `run_sandbox`
- Worktree manager (create/cleanup)
- PID file writer (application.ex)
- GitHub issue source (polls for `self-improvement` label)

### Modified modules
- `StepRunner` — expand dangerous tools list, add worktree context passing
- `LearningLoop` — wire into step completion callback
- `Sandbox` — support worktree paths, expand command allowlist
- `Application` — write PID file on boot, check for pending restart confirmations
- Tool registry — register new tools

### New files
- `bin/restart.sh`
- `bin/restart-docker.sh`

### Config
- Model configurable per member (default: Ollama)
- Polling interval for GitHub issue source (default: 5 min)
- Auto-merge risk threshold (PM decides, but configurable default)
