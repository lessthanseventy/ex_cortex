# The Forge — AI Pipeline Builder

**Date:** 2026-03-15
**Goal:** Natural language → rumination pipeline. Describe what you want, get a proposed pipeline, accept or refine.

## Route & UI

`/forge` — own page in nav between Ruminations and Memory.

### Phase 1: Describe
- Text area for natural language description
- Model selector (defaults to strongest available: Claude > devstral > ministral)
- "Forge" button → calls LLM with inventory context

### Phase 2: Review
- Proposed pipeline renders as visual synapse chain (reuse ruminations display pattern)
- Each step shows: name, cluster, neuron, output type, description
- Two actions: **Accept** (creates rumination, paused) or **Refine** (inline editing)

### Refine Mode
- Steps become editable inline — reorder, delete, add, change cluster/neuron/output
- Pre-populated from AI proposal
- "Save" creates the rumination when done

## Backend: ExCortex.Forge

### Context gathering
1. Start with summary inventory (cluster names + neuron names/ranks)
2. Include system reference axiom
3. If LLM proposes nonexistent neurons → auto-retry with full inventory (system prompts included)

### LLM prompt
System prompt instructs the LLM to output structured JSON:
```json
{
  "name": "Research Digest: Elixir 1.19",
  "description": "...",
  "trigger": "manual",
  "steps": [
    {
      "name": "Gather: Elixir 1.19 Features",
      "description": "...",
      "cluster_name": "Research",
      "preferred_neuron": "Gatherer",
      "output_type": "freeform"
    }
  ]
}
```

### Pipeline creation
- Parse JSON response
- Create synapses from steps
- Create rumination referencing synapse IDs, status: "paused"
- Return the created rumination for display

## Model selection
- Default: strongest available (check Claude keys first, fall back to devstral)
- User can override via selector on the page
- Uses `Settings.resolve/2` + `ExCortex.LLM` for the actual call
