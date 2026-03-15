# Streaming Pipeline Output

**Date:** 2026-03-15
**Goal:** Stream rumination step outputs to the UI as they happen, not just at completion.

## Current State

- LLM providers (`Ollama.complete/4`, `Claude.complete/4`) return complete responses
- Runner processes steps synchronously, broadcasts only `daydream_started` and `daydream_completed`
- UI shows "Running..." then jumps to final state
- Ollama API supports `stream: true` returning Server-Sent Events
- Claude API supports streaming via `ReqLLM`

## Proposed Architecture

### Layer 1: Step-level progress (quick win)
Broadcast after each step completes, not just at pipeline end:
- New PubSub message: `{:step_completed, %{daydream_id, step_index, step_name, status, output_preview}}`
- Runner already has this info at the end of `run_regular_step` — just add a broadcast
- UI subscribes and renders step progress incrementally
- No LLM changes needed

### Layer 2: Token-level streaming (full experience)
Stream LLM tokens to the UI as they're generated:
- Add `complete_stream/4` to LLM providers that returns a Stream/GenStage
- Runner wraps each step in a stream consumer that broadcasts tokens via PubSub
- UI receives token chunks and appends to a live-updating display
- Needs careful backpressure handling — don't flood the browser

### Layer 3: Tool call visibility
When the LLM makes tool calls during a step:
- Broadcast `{:tool_call, %{daydream_id, step_index, tool_name, args}}`
- Broadcast `{:tool_result, %{daydream_id, step_index, tool_name, result}}`
- UI shows tool calls happening in real time
- Especially valuable for dry run mode — watch the "would have called X" messages appear

## Recommended Implementation Order

1. **Step-level progress** — 1-2 hours, massive UX improvement for minimal change
2. **Tool call visibility** — builds on step progress, adds tool broadcasting
3. **Token streaming** — bigger change to LLM layer, best value for long-running steps

## UI Design

The run history expanded view (daydream_row) becomes a live-updating display:
- Steps appear one by one as they complete
- Currently-running step shows a spinner/pulse
- Tool calls appear as sub-items under the active step
- Token streaming (Layer 3) shows text appearing character by character

Could also add a dedicated "Live Run" panel that appears when a rumination is running,
replacing or augmenting the current run history view.
