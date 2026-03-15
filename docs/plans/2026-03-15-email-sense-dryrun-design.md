# Email Sense (notmuch) + Dry Run Mode

**Date:** 2026-03-15
**Goal:** Wire up the Email sense to the local notmuch instance, and add a dry run mode so ruminations can preview what they'd do without actually doing it.

## Email Sense: notmuch Integration

### How notmuch works
- `notmuch` indexes a local Maildir
- `notmuch search` / `notmuch show` query by tags, dates, threads
- The CLI tools are already detected at boot (in `@cli_tools`)
- Config: query string, interval, max results per poll

### Sense Worker
The email sense worker polls notmuch on an interval:
1. Run `notmuch search --format=json --output=summary <query>` to get new threads
2. Track last-seen message ID in sense state to avoid re-processing
3. For each new thread, run `notmuch show --format=json <thread_id>` to get full content
4. Push each message/thread as input to any ruminations triggered by this sense

### Default Config
```json
{
  "query": "tag:inbox AND tag:unread",
  "interval": 600000,
  "max_results": 50,
  "format": "thread"
}
```

### What the rumination receives
Each triggered run gets a structured input:
```
Subject: Re: Q3 Planning
From: alice@example.com
Date: 2026-03-15 10:30
Tags: inbox, unread, work
Thread: 5 messages

[Latest message body here]
```

## Dry Run Mode

### The Problem
Ruminations with real side effects (deleting emails, filing GitHub issues, posting to Slack) are scary to run without knowing what they'll do first.

### Design
Add a `dry_run` option to `Runner.run/3`:
- When `dry_run: true`, the runner executes all steps normally BUT:
  - Tool calls that have side effects are intercepted and logged instead of executed
  - The LLM still sees the tool call format, but gets a simulated response
  - No signals are posted, no engrams created, no external actions taken
- The daydream is saved with status `"dry_run"` and full synapse_results
- The UI shows the dry run output so you can review what *would* happen

### Which tools are "dangerous" in dry run?
Already have `dangerous_tool_mode` on synapses with values: `execute`, `intercept`, `dry_run`. The infrastructure exists — dry run mode just forces all steps to `dry_run` regardless of their individual setting.

### UI Changes
- Add a "Dry Run" button next to "Run" on the ruminations detail page
- Dry run daydreams show with a distinct color (cyan?) in run history
- Dry run results are clearly labeled "DRY RUN — no actions were taken"

### Implementation
1. `Runner.run/3` accepts `opts` keyword list with `dry_run: true`
2. In `ImpulseRunner`, when dry_run is active, tool calls return `{:dry_run, tool_name, args}` instead of executing
3. The LLM sees "Tool call intercepted (dry run): <tool_name>(<args>)" as the tool result
4. Daydream saved with status "dry_run"
5. No PubSub broadcasts for signal/engram creation in dry run mode

## Implementation Order
1. Email sense worker (notmuch polling + thread parsing)
2. Dry run mode on Runner/ImpulseRunner
3. UI: dry run button + display
4. Wire email sense to a rumination via Genesis
