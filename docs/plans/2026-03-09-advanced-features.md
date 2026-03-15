# Advanced Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement seven quality-of-life and architectural features: model fallback chains, Reality Checker member, rank-gated quest eligibility, structured campaign handoff context, parallel campaign workstreams, guild charter documents, and member trust scoring — plus a Guide page.

**Architecture:** Independent features are grouped by dependency. Tasks 1–3 have no prerequisites. Tasks 4–5 require the behavioral campaigns plan (`docs/plans/2026-03-09-behavioral-campaigns.md`) to be complete first — specifically `CampaignRunner` must exist. Tasks 6–8 are independent. All follow TDD: failing test → minimal implementation → passing test → commit.

**Tech Stack:** Elixir/Phoenix, Ecto, LiveView, GenServer, Task.async_stream, Ollama

**PREREQUISITE:** Complete `docs/plans/2026-03-09-behavioral-campaigns.md` before starting Task 4.

---

## Task 1: Model Fallback Chains

**Files:**
- Modify: `lib/ex_cortex/quest_runner.ex:184-194`
- Modify: `config/config.exs`
- Test: `test/ex_cortex/quest_runner_test.exs`

**Background:** When Ollama fails for the assigned model, `call_member` currently returns `%{verdict: "abstain"}` immediately. We want it to retry with fallback models before giving up.

**Step 1: Add config**

In `config/config.exs`, add after existing ex_cortex config:

```elixir
config :ex_cortex, :model_fallback_chain, ["phi4-mini", "gemma3:4b", "llama3:8b"]
```

**Step 2: Write the failing test**

In `test/ex_cortex/quest_runner_test.exs`, add a describe block:

```elixir
describe "model fallback chains" do
  test "call_member_with_fallback/3 returns abstain only after all models fail" do
    # We test the public behavior indirectly: if the assigned model isn't in
    # the fallback chain, we still try it first, then the chain.
    # Direct unit test: verify fallback_models_for/1 returns correct order.
    assigned = "missing-model"
    chain = ["phi4-mini", "gemma3:4b"]
    result = ExCortex.QuestRunner.fallback_models_for(assigned, chain)
    assert result == ["missing-model", "phi4-mini", "gemma3:4b"]
  end

  test "fallback_models_for/2 deduplicates when assigned model is in chain" do
    assigned = "phi4-mini"
    chain = ["phi4-mini", "gemma3:4b"]
    result = ExCortex.QuestRunner.fallback_models_for(assigned, chain)
    assert result == ["phi4-mini", "gemma3:4b"]
  end
end
```

**Step 3: Run to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/quest_runner_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: `function ExCortex.QuestRunner.fallback_models_for/2 is undefined`

**Step 4: Implement**

In `lib/ex_cortex/quest_runner.ex`, add this public function after the module attributes:

```elixir
@doc "Build the ordered list of models to try: assigned model first, then fallback chain (deduped)."
def fallback_models_for(model, chain) do
  [model | Enum.reject(chain, &(&1 == model))]
end
```

Replace the existing `call_member` for Ollama (lines 184-195):

```elixir
defp call_member(%{type: :ollama, model: model, system_prompt: system_prompt}, input_text, ollama) do
  chain = Application.get_env(:ex_cortex, :model_fallback_chain, [])
  models = fallback_models_for(model, chain)

  messages = [
    %{role: :system, content: system_prompt},
    %{role: :user, content: input_text}
  ]

  Enum.reduce_while(models, %{verdict: "abstain", confidence: 0.0, reason: "Ollama error"}, fn m, acc ->
    case Ollama.chat(ollama, m, messages) do
      {:ok, %{content: text}} -> {:halt, parse_verdict(text)}
      {:ok, text} when is_binary(text) -> {:halt, parse_verdict(text)}
      _ -> {:cont, acc}
    end
  end)
end
```

**Step 5: Run tests**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/quest_runner_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: All tests pass.

**Step 6: Commit**

```bash
git add config/config.exs lib/ex_cortex/quest_runner.ex test/ex_cortex/quest_runner_test.exs
git commit -m "feat: model fallback chains — retry with configured models on Ollama failure"
```

---

## Task 2: Reality Checker Builtin Member

**Files:**
- Modify: `lib/ex_cortex/members/member.ex`
- Modify: `lib/ex_cortex/quest_runner.ex`
- Test: `test/ex_cortex/quest_runner_test.exs`

**Background:** Add a "Challenger" builtin member in a new `validators()` category. Resolves via `"who": "challenger"` in any roster step. Defaults to skepticism and demands evidence.

**Step 1: Write the failing test**

In `test/ex_cortex/quest_runner_test.exs`, add:

```elixir
describe "challenger member" do
  test "resolve_members returns a single challenger spec" do
    # Call the private function via the module's behavior:
    # We test that BuiltinMember.get("challenger") returns a member
    member = ExCortex.Members.BuiltinMember.get("challenger")
    assert member != nil
    assert member.id == "challenger"
    assert member.category == :validator
    assert String.contains?(member.system_prompt, "evidence")
  end
end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/quest_runner_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: assertion fails because `get("challenger")` returns `nil`.

**Step 3: Add validators() to BuiltinMember**

In `lib/ex_cortex/members/member.ex`:

1. Update `def all`:

```elixir
def all, do: editors() ++ analysts() ++ specialists() ++ advisors() ++ validators()
```

2. Add the new function at the bottom before `get/1`:

```elixir
defp validators do
  [
    %__MODULE__{
      id: "challenger",
      name: "Challenger",
      description: "Demands evidence for all claims. Defaults to NEEDS WORK unless concrete proof is provided.",
      category: :validator,
      ranks: @default_ranks,
      system_prompt: """
      You are a skeptic and evidence-demanding challenger. Your job is to find holes in prior verdicts and claims.

      Rules:
      - Never accept vague assertions. Demand specific, concrete evidence.
      - Default to NEEDS WORK (fail) unless verifiable evidence is provided.
      - Call out circular reasoning, unsupported assumptions, and hand-waving.
      - If a prior verdict says "pass" without citing specific evidence, reject it.

      Respond with:
      ACTION: pass | warn | fail | abstain
      CONFIDENCE: 0.0-1.0
      REASON: your reasoning, citing what evidence was or wasn't present
      """
    }
  ]
end
```

**Step 4: Add resolver clause in QuestRunner**

In `lib/ex_cortex/quest_runner.ex`, add after `resolve_members("master")` (around line 124):

```elixir
defp resolve_members("challenger") do
  case ExCortex.Members.BuiltinMember.get("challenger") do
    nil ->
      []

    member ->
      rank_config = member.ranks[:journeyman]
      [
        %{
          type: :ollama,
          model: rank_config.model,
          system_prompt: member.system_prompt,
          name: member.name
        }
      ]
  end
end
```

**Step 5: Run tests**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/quest_runner_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: All tests pass.

**Step 6: Commit**

```bash
git add lib/ex_cortex/members/member.ex lib/ex_cortex/quest_runner.ex test/ex_cortex/quest_runner_test.exs
git commit -m "feat: add Challenger builtin member — evidence-demanding skeptic for roster validation steps"
```

---

## Task 3: Rank-Gated Quest Eligibility

**Files:**
- Create: `priv/repo/migrations/20260309010000_add_min_rank_to_quests.exs`
- Modify: `lib/ex_cortex/quests/quest.ex`
- Modify: `lib/ex_cortex/quest_runner.ex`
- Test: `test/ex_cortex/quest_runner_test.exs`

**Background:** Quests can declare a `min_rank` requirement (`"apprentice"` / `"journeyman"` / `"master"`). If set, `QuestRunner` checks that at least one active member meets or exceeds that rank before running. Returns `{:error, {:rank_insufficient, reason}}` if not.

**Step 1: Create migration**

```elixir
# priv/repo/migrations/20260309010000_add_min_rank_to_quests.exs
defmodule ExCortex.Repo.Migrations.AddMinRankToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :min_rank, :string, null: true
    end
  end
end
```

**Step 2: Run migration**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix ecto.migrate 2>&1' --pane=main:1.3
```

Expected: `== Running 20260309010000 AddMinRankToQuests`

**Step 3: Add field to Quest schema**

In `lib/ex_cortex/quests/quest.ex`, add after the `herald_name` field:

```elixir
field :min_rank, :string
```

Also add to the changeset's cast and validate_inclusion (find the changeset function):

```elixir
|> cast(attrs, [...existing fields..., :min_rank])
|> validate_inclusion(:min_rank, ~w(apprentice journeyman master), message: "must be apprentice, journeyman, or master")
```

**Step 4: Write the failing test**

In `test/ex_cortex/quest_runner_test.exs`, add:

```elixir
describe "rank-gated eligibility" do
  test "run/2 returns rank_insufficient when no members meet min_rank" do
    # No members in test DB, so any rank gate will fail
    quest = %ExCortex.Quests.Quest{
      id: 1,
      name: "Gated Quest",
      min_rank: "master",
      roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}],
      context_providers: [],
      output_type: "verdict"
    }

    assert {:error, {:rank_insufficient, _reason}} = ExCortex.QuestRunner.run(quest, "input")
  end

  test "run/2 proceeds normally when min_rank is nil" do
    quest = %ExCortex.Quests.Quest{
      id: 2,
      name: "Open Quest",
      min_rank: nil,
      roster: [],
      context_providers: [],
      output_type: "verdict"
    }

    # Empty roster returns an error but NOT rank_insufficient
    result = ExCortex.QuestRunner.run(quest, "input")
    assert result != {:error, {:rank_insufficient, "Quest requires master or higher — no eligible members found"}}
  end
end
```

**Step 5: Run to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/quest_runner_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: First test fails — quest runs instead of returning rank_insufficient.

**Step 6: Implement rank gate**

In `lib/ex_cortex/quest_runner.ex`, add a new `run/2` clause for quest structs with `min_rank`. Add this BEFORE the existing `def run(quest, input_text) when is_struct(quest)` clause:

```elixir
@rank_order %{"apprentice" => 0, "journeyman" => 1, "master" => 2}

def run(%{min_rank: min_rank} = quest, input_text)
    when is_binary(min_rank) and min_rank != "" do
  min_order = Map.get(@rank_order, min_rank, 0)

  eligible_ranks =
    @rank_order
    |> Enum.filter(fn {_rank, order} -> order >= min_order end)
    |> Enum.map(fn {rank, _} -> rank end)

  has_eligible =
    Repo.exists?(
      from m in Member,
        where:
          m.type == "role" and m.status == "active" and
            fragment("config->>'rank' = ANY(?)", ^eligible_ranks)
    )

  if has_eligible do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"
    run(quest.roster, augmented)
  else
    {:error, {:rank_insufficient, "Quest requires #{min_rank} or higher — no eligible members found"}}
  end
end
```

**Step 7: Run tests**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/quest_runner_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: All tests pass.

**Step 8: Run full test suite**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: All tests pass.

**Step 9: Commit**

```bash
git add priv/repo/migrations/20260309010000_add_min_rank_to_quests.exs lib/ex_cortex/quests/quest.ex lib/ex_cortex/quest_runner.ex test/ex_cortex/quest_runner_test.exs
git commit -m "feat: rank-gated quest eligibility — min_rank blocks run if no eligible members exist"
```

---

## Task 4: Structured Handoff Context in CampaignRunner

**PREREQUISITE:** Complete `docs/plans/2026-03-09-behavioral-campaigns.md` first. `CampaignRunner` must exist at `lib/ex_cortex/campaign_runner.ex`.

**Files:**
- Modify: `lib/ex_cortex/campaign_runner.ex`
- Test: `test/ex_cortex/campaign_runner_test.exs`

**Background:** Replace free-text context threading with a structured handoff block that tells each subsequent member: what was checked, what the verdict was, and what question to focus on. The next quest's name drives the "open question" line.

**Step 1: Write the failing test**

In `test/ex_cortex/campaign_runner_test.exs`, add:

```elixir
describe "structured handoff" do
  test "result_to_text/3 formats a structured handoff block" do
    result = {:ok, %{verdict: "pass", steps: [
      %{who: "all", verdict: "pass", results: [%{member: "Analyst", verdict: "pass", reason: "Evidence found"}]}
    ]}}
    text = ExCortex.CampaignRunner.result_to_text(result, "Accuracy Check", "Tone Review")
    assert String.contains?(text, "## Prior Step: Accuracy Check")
    assert String.contains?(text, "**Verdict:** pass")
    assert String.contains?(text, "Analyst")
    assert String.contains?(text, "Tone Review")
  end

  test "result_to_text/3 formats artifact handoff" do
    result = {:ok, %{artifact: %{title: "Report", body: "Body text"}}}
    text = ExCortex.CampaignRunner.result_to_text(result, "Draft Step", "Review Step")
    assert String.contains?(text, "## Prior Step: Draft Step")
    assert String.contains?(text, "Report")
    assert String.contains?(text, "Review Step")
  end

  test "result_to_text/3 with nil next_quest_name omits question line" do
    result = {:ok, %{verdict: "pass", steps: []}}
    text = ExCortex.CampaignRunner.result_to_text(result, "Final Step", nil)
    refute String.contains?(text, "Open question")
  end
end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/campaign_runner_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: `result_to_text/3 is undefined` (only `result_to_text/1` exists).

**Step 3: Update CampaignRunner**

In `lib/ex_cortex/campaign_runner.ex`, replace the `run/2` implementation and `result_to_text/1` functions with:

```elixir
def run(%{steps: steps} = campaign, input) when steps == [] do
  Logger.info("[CampaignRunner] Campaign #{campaign.id} (#{campaign.name}) has no steps")
  {:ok, %{steps: []}}
end

def run(campaign, input) do
  ordered_steps = Enum.sort_by(campaign.steps, &Map.get(&1, "order", 0))

  Logger.info(
    "[CampaignRunner] Running campaign #{campaign.id} (#{campaign.name}), #{length(ordered_steps)} step(s)"
  )

  # Zip each step with the next step for look-ahead (next quest name for handoff)
  steps_with_next = Enum.zip(ordered_steps, tl(ordered_steps) ++ [nil])

  {results, _} =
    Enum.reduce(steps_with_next, {[], input}, fn {step, next_step}, {acc_results, current_input} ->
      quest_id = step["quest_id"]
      next_quest_name = if next_step, do: resolve_quest_name(next_step["quest_id"]), else: nil

      case resolve_quest(quest_id) do
        nil ->
          Logger.warning("[CampaignRunner] Quest #{quest_id} not found, skipping step")
          {acc_results ++ [{:error, :quest_not_found}], current_input}

        quest ->
          Logger.info("[CampaignRunner] Running step quest #{quest.id} (#{quest.name})")
          result = QuestRunner.run(quest, current_input)

          next_input =
            case result_to_text(result, quest.name, next_quest_name) do
              "" -> current_input
              text -> "#{current_input}\n\n#{text}"
            end

          {acc_results ++ [result], next_input}
      end
    end)

  case List.last(results) do
    {:ok, _} = ok -> ok
    _ -> {:ok, %{steps: results}}
  end
end

@doc "Format a QuestRunner result as a structured handoff block for the next step."
def result_to_text(result, current_quest_name, next_quest_name)

def result_to_text({:ok, %{verdict: verdict, steps: steps}}, quest_name, next_quest_name) do
  member_lines =
    steps
    |> Enum.flat_map(& &1.results)
    |> Enum.map_join("\n", fn r -> "- **#{r.member}:** #{r.verdict} — #{String.slice(r[:reason] || "", 0, 120)}" end)

  question =
    if next_quest_name,
      do: "\n**Open question for #{next_quest_name}:** What does this verdict imply for your evaluation?",
      else: ""

  """
  ## Prior Step: #{quest_name}
  **Verdict:** #{verdict}
  **Member findings:**
  #{member_lines}#{question}
  """
end

def result_to_text({:ok, %{artifact: %{title: title, body: body}}}, quest_name, next_quest_name) do
  question =
    if next_quest_name,
      do: "\n**Open question for #{next_quest_name}:** How does this artifact inform your evaluation?",
      else: ""

  """
  ## Prior Step: #{quest_name}
  **Artifact:** #{title}
  #{body}#{question}
  """
end

def result_to_text({:ok, %{delivered: true, type: type}}, quest_name, _next) do
  "## Prior Step: #{quest_name}\nHerald delivered (#{type})\n"
end

def result_to_text(_, _, _), do: ""

# Keep the arity-1 version for backwards compatibility
def result_to_text(result), do: result_to_text(result, "Previous Step", nil)

defp resolve_quest_name(quest_id) when is_binary(quest_id) do
  case resolve_quest(quest_id) do
    nil -> quest_id
    quest -> quest.name
  end
end

defp resolve_quest_name(_), do: nil
```

**Step 4: Run tests**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/campaign_runner_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex/campaign_runner.ex test/ex_cortex/campaign_runner_test.exs
git commit -m "feat: structured handoff context between campaign steps — verdict, findings, open question"
```

---

## Task 5: Parallel Workstreams in Campaigns (Branch Steps)

**PREREQUISITE:** Task 4 must be complete.

**Files:**
- Modify: `lib/ex_cortex/campaign_runner.ex`
- Test: `test/ex_cortex/campaign_runner_test.exs`

**Background:** Campaign steps gain an optional `"type": "branch"` field. Branch steps run multiple quests in parallel and feed all results to a synthesizer quest. Sequential steps are unchanged.

A branch step looks like:
```json
{
  "type": "branch",
  "quests": ["quest_id_1", "quest_id_2"],
  "synthesizer": "quest_id_3",
  "order": 2
}
```

**Step 1: Write the failing test**

In `test/ex_cortex/campaign_runner_test.exs`, add:

```elixir
describe "branch steps" do
  test "run/2 with a branch step runs all quests and synthesizer" do
    {:ok, q1} = Quests.create_quest(%{name: "Branch A", trigger: "manual", output_type: "verdict",
      roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]})
    {:ok, q2} = Quests.create_quest(%{name: "Branch B", trigger: "manual", output_type: "verdict",
      roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]})
    {:ok, synth} = Quests.create_quest(%{name: "Synthesizer", trigger: "manual", output_type: "verdict",
      roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]})

    {:ok, campaign} = Quests.create_campaign(%{
      name: "Branch Campaign",
      trigger: "manual",
      steps: [
        %{
          "type" => "branch",
          "quests" => [to_string(q1.id), to_string(q2.id)],
          "synthesizer" => to_string(synth.id),
          "order" => 1
        }
      ]
    })

    result = ExCortex.CampaignRunner.run(campaign, "test input")
    assert match?({:ok, _} | {:error, _}, result)
  end

  test "combine_branch_results/2 joins multiple results into one context block" do
    results = [
      {{:ok, %{verdict: "pass", steps: []}}, "Quest Alpha"},
      {{:ok, %{verdict: "fail", steps: []}}, "Quest Beta"}
    ]
    combined = ExCortex.CampaignRunner.combine_branch_results(results, "input")
    assert String.contains?(combined, "Quest Alpha")
    assert String.contains?(combined, "Quest Beta")
    assert String.contains?(combined, "pass")
    assert String.contains?(combined, "fail")
  end
end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/campaign_runner_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: `combine_branch_results/2 is undefined`

**Step 3: Implement branch step handling**

In `lib/ex_cortex/campaign_runner.ex`, update the step dispatch in `run/2`. Replace the step-processing reduce body:

The `steps_with_next` reduce currently handles one step type. Add branch detection:

```elixir
# In the reduce, replace the inner logic with:
{step, next_step}, {acc_results, current_input} ->
  case step["type"] do
    "branch" ->
      next_quest_name = if next_step, do: resolve_quest_name(next_step["quest_id"] || next_step["synthesizer"]), else: nil
      result = run_branch_step(step, current_input)

      synth_quest_name =
        step["synthesizer"] |> resolve_quest() |> case do
          nil -> "Branch"
          q -> q.name
        end

      next_input =
        case result_to_text(result, "Branch: #{synth_quest_name}", next_quest_name) do
          "" -> current_input
          text -> "#{current_input}\n\n#{text}"
        end

      {acc_results ++ [result], next_input}

    _ ->
      # existing sequential step logic (quest_id path)
      quest_id = step["quest_id"]
      next_quest_name = if next_step, do: resolve_quest_name(next_step["quest_id"]), else: nil

      case resolve_quest(quest_id) do
        nil ->
          Logger.warning("[CampaignRunner] Quest #{quest_id} not found, skipping step")
          {acc_results ++ [{:error, :quest_not_found}], current_input}

        quest ->
          Logger.info("[CampaignRunner] Running step quest #{quest.id} (#{quest.name})")
          result = QuestRunner.run(quest, current_input)

          next_input =
            case result_to_text(result, quest.name, next_quest_name) do
              "" -> current_input
              text -> "#{current_input}\n\n#{text}"
            end

          {acc_results ++ [result], next_input}
      end
  end
```

Then add the branch step functions:

```elixir
defp run_branch_step(step, input) do
  quest_ids = step["quests"] || []
  synthesizer_id = step["synthesizer"]

  Logger.info("[CampaignRunner] Running branch step: #{length(quest_ids)} parallel quest(s) + synthesizer")

  # Run branch quests in parallel
  branch_results =
    quest_ids
    |> Task.async_stream(
      fn quest_id ->
        case resolve_quest(quest_id) do
          nil ->
            {quest_id, {:error, :quest_not_found}}

          quest ->
            Logger.info("[CampaignRunner] Branch: running #{quest.name}")
            {quest.name, QuestRunner.run(quest, input)}
        end
      end,
      timeout: 120_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _} -> {"unknown", {:error, :timeout}}
    end)

  combined_input = combine_branch_results(branch_results, input)

  case resolve_quest(synthesizer_id) do
    nil ->
      Logger.warning("[CampaignRunner] Branch synthesizer #{synthesizer_id} not found")
      {:error, :synthesizer_not_found}

    synth ->
      Logger.info("[CampaignRunner] Branch: running synthesizer #{synth.name}")
      QuestRunner.run(synth, combined_input)
  end
end

@doc "Combine parallel branch results into a single context block for the synthesizer."
def combine_branch_results(named_results, original_input) do
  branch_context =
    named_results
    |> Enum.map_join("\n\n", fn {name, result} ->
      result_to_text(result, name, nil)
    end)

  """
  #{original_input}

  ## Parallel Branch Results

  #{branch_context}
  """
end
```

**Step 4: Run tests**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/campaign_runner_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: All tests pass.

**Step 5: Run full suite**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test --seed 0 2>&1 | tail -20' --pane=main:1.3
```

**Step 6: Commit**

```bash
git add lib/ex_cortex/campaign_runner.ex test/ex_cortex/campaign_runner_test.exs
git commit -m "feat: parallel campaign workstreams — branch steps run quests concurrently and synthesize"
```

---

## Task 6: Guild Charter Document

**Files:**
- Create: `priv/repo/migrations/20260309020000_create_guild_charters.exs`
- Create: `lib/ex_cortex/guild_charters/guild_charter.ex`
- Create: `lib/ex_cortex/guild_charters.ex`
- Create: `lib/ex_cortex/context_providers/guild_charter.ex`
- Modify: `lib/ex_cortex/context_providers/context_provider.ex`
- Modify: `lib/ex_cortex_web/live/guild_hall_live.ex`
- Test: `test/ex_cortex/guild_charters_test.exs`

**Background:** Each guild (identified by name) can have a charter document — shared values, domain rules, output format expectations. It's stored in `guild_charters` and prepended to member inputs via a new `"guild_charter"` context provider type. Editable in Guild Hall.

**Step 1: Create migration**

```elixir
# priv/repo/migrations/20260309020000_create_guild_charters.exs
defmodule ExCortex.Repo.Migrations.CreateGuildCharters do
  use Ecto.Migration

  def change do
    create table(:guild_charters) do
      add :guild_name, :string, null: false
      add :charter_text, :text, null: false, default: ""
      timestamps()
    end

    create unique_index(:guild_charters, [:guild_name])
  end
end
```

**Step 2: Run migration**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix ecto.migrate 2>&1' --pane=main:1.3
```

**Step 3: Write the failing test**

```elixir
# test/ex_cortex/guild_charters_test.exs
defmodule ExCortex.GuildChartersTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.GuildCharters

  test "upsert_charter/2 creates a charter for a guild" do
    assert {:ok, charter} = GuildCharters.upsert_charter("TestGuild", "Our values: honesty.")
    assert charter.guild_name == "TestGuild"
    assert charter.charter_text == "Our values: honesty."
  end

  test "upsert_charter/2 updates an existing charter" do
    {:ok, _} = GuildCharters.upsert_charter("TestGuild", "v1")
    {:ok, updated} = GuildCharters.upsert_charter("TestGuild", "v2")
    assert updated.charter_text == "v2"
  end

  test "get_charter/1 returns nil when no charter exists" do
    assert GuildCharters.get_charter("NoSuchGuild") == nil
  end

  test "get_charter/1 returns charter text when it exists" do
    {:ok, _} = GuildCharters.upsert_charter("MyGuild", "Be excellent.")
    assert GuildCharters.get_charter("MyGuild") == "Be excellent."
  end
end
```

**Step 4: Run to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/guild_charters_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: `ExCortex.GuildCharters is not loaded`

**Step 5: Create schema**

```elixir
# lib/ex_cortex/guild_charters/guild_charter.ex
defmodule ExCortex.GuildCharters.GuildCharter do
  use Ecto.Schema
  import Ecto.Changeset

  schema "guild_charters" do
    field :guild_name, :string
    field :charter_text, :string, default: ""
    timestamps()
  end

  def changeset(charter, attrs) do
    charter
    |> cast(attrs, [:guild_name, :charter_text])
    |> validate_required([:guild_name])
  end
end
```

**Step 6: Create context module**

```elixir
# lib/ex_cortex/guild_charters.ex
defmodule ExCortex.GuildCharters do
  import Ecto.Query
  alias ExCortex.GuildCharters.GuildCharter
  alias ExCortex.Repo

  def get_charter(guild_name) do
    case Repo.get_by(GuildCharter, guild_name: guild_name) do
      nil -> nil
      charter -> charter.charter_text
    end
  end

  def upsert_charter(guild_name, charter_text) do
    %GuildCharter{}
    |> GuildCharter.changeset(%{guild_name: guild_name, charter_text: charter_text})
    |> Repo.insert(
      on_conflict: [set: [charter_text: charter_text, updated_at: DateTime.utc_now()]],
      conflict_target: :guild_name,
      returning: true
    )
  end

  def list_charters do
    Repo.all(from c in GuildCharter, order_by: c.guild_name)
  end
end
```

**Step 7: Create context provider**

```elixir
# lib/ex_cortex/context_providers/guild_charter.ex
defmodule ExCortex.ContextProviders.GuildCharter do
  @moduledoc """
  Prepends the guild's charter document to the evaluation input.
  Config: %{"guild_name" => "MyGuild"}
  """

  def call(%{"guild_name" => guild_name}, _quest, _input) when is_binary(guild_name) do
    case ExCortex.GuildCharters.get_charter(guild_name) do
      nil -> ""
      "" -> ""
      text -> "## Guild Charter: #{guild_name}\n#{text}"
    end
  end

  def call(_, _, _), do: ""
end
```

**Step 8: Register provider**

In `lib/ex_cortex/context_providers/context_provider.ex`, add to `module_for/1`:

```elixir
defp module_for("guild_charter"), do: Module.concat([ExCortex, ContextProviders, GuildCharter])
```

**Step 9: Run tests**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/guild_charters_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

**Step 10: Add Charter UI to Guild Hall**

In `lib/ex_cortex_web/live/guild_hall_live.ex`:

1. Add `alias ExCortex.GuildCharters` near the top.

2. In `mount/3`, load charters:
```elixir
charters = GuildCharters.list_charters() |> Map.new(& {&1.guild_name, &1.charter_text})
socket = assign(socket, charters: charters, editing_charter: nil)
```

3. Add event handlers:
```elixir
def handle_event("edit_charter", %{"guild" => guild_name}, socket) do
  {:noreply, assign(socket, editing_charter: guild_name)}
end

def handle_event("save_charter", %{"guild_name" => guild_name, "charter_text" => text}, socket) do
  {:ok, _} = GuildCharters.upsert_charter(guild_name, text)
  charters = GuildCharters.list_charters() |> Map.new(& {&1.guild_name, &1.charter_text})
  {:noreply, assign(socket, charters: charters, editing_charter: nil)}
end

def handle_event("cancel_charter", _, socket) do
  {:noreply, assign(socket, editing_charter: nil)}
end
```

4. In the render, for each installed guild card, add a charter section below the member list. Find where guild cards render (look for the guild name display) and append:

```heex
<div class="mt-3 border-t pt-3">
  <div class="text-xs font-medium text-muted-foreground mb-1">Guild Charter</div>
  <%= if @editing_charter == guild.name do %>
    <form phx-submit="save_charter">
      <input type="hidden" name="guild_name" value={guild.name} />
      <textarea name="charter_text" class="w-full text-xs font-mono border rounded p-2 h-24"
        placeholder="Shared values, domain rules, output expectations..."><%= Map.get(@charters, guild.name, "") %></textarea>
      <div class="flex gap-2 mt-1">
        <.button type="submit" size="sm">Save</.button>
        <.button type="button" phx-click="cancel_charter" variant="ghost" size="sm">Cancel</.button>
      </div>
    </form>
  <% else %>
    <p class="text-xs text-muted-foreground italic">
      <%= if charter = Map.get(@charters, guild.name), do: String.slice(charter, 0, 100) <> "…", else: "No charter set" %>
    </p>
    <.button phx-click="edit_charter" phx-value-guild={guild.name} variant="ghost" size="sm" class="mt-1">
      Edit Charter
    </.button>
  <% end %>
</div>
```

**Step 11: Run full test suite**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test --seed 0 2>&1 | tail -20' --pane=main:1.3
```

**Step 12: Commit**

```bash
git add priv/repo/migrations/20260309020000_create_guild_charters.exs lib/ex_cortex/guild_charters/ lib/ex_cortex/guild_charters.ex lib/ex_cortex/context_providers/guild_charter.ex lib/ex_cortex/context_providers/context_provider.ex lib/ex_cortex_web/live/guild_hall_live.ex test/ex_cortex/guild_charters_test.exs
git commit -m "feat: guild charter document — per-guild context injected into all member evaluations"
```

---

## Task 7: Member Trust Scoring

**Files:**
- Create: `priv/repo/migrations/20260309030000_create_member_trust_scores.exs`
- Create: `lib/ex_cortex/trust/member_trust_score.ex`
- Create: `lib/ex_cortex/trust_scorer.ex`
- Modify: `lib/ex_cortex/quest_runner.ex`
- Modify: `lib/ex_cortex_web/live/lodge_live.ex`
- Test: `test/ex_cortex/trust_scorer_test.exs`

**Background:** Each member (by name) gets a trust score starting at 1.0. When a member's individual verdict contradicts the aggregated step verdict, their score decays by ×0.97. Scores surface in Lodge as a sortable "Member Trust" panel.

**Step 1: Create migration**

```elixir
# priv/repo/migrations/20260309030000_create_member_trust_scores.exs
defmodule ExCortex.Repo.Migrations.CreateMemberTrustScores do
  use Ecto.Migration

  def change do
    create table(:member_trust_scores) do
      add :member_name, :string, null: false
      add :score, :float, null: false, default: 1.0
      add :decay_count, :integer, null: false, default: 0
      timestamps()
    end

    create unique_index(:member_trust_scores, [:member_name])
  end
end
```

**Step 2: Run migration**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix ecto.migrate 2>&1' --pane=main:1.3
```

**Step 3: Write the failing test**

```elixir
# test/ex_cortex/trust_scorer_test.exs
defmodule ExCortex.TrustScorerTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.TrustScorer

  test "list_scores/0 returns empty list initially" do
    assert TrustScorer.list_scores() == []
  end

  test "decay/1 creates a score record at initial score below 1.0" do
    TrustScorer.decay("Alice")
    scores = TrustScorer.list_scores()
    assert length(scores) == 1
    [score] = scores
    assert score.member_name == "Alice"
    assert score.score < 1.0
    assert score.decay_count == 1
  end

  test "decay/1 called twice further reduces score" do
    TrustScorer.decay("Bob")
    TrustScorer.decay("Bob")
    [score] = TrustScorer.list_scores()
    assert score.decay_count == 2
    assert score.score < 0.97
  end

  test "record_run/1 decays members whose verdict contradicts step verdict" do
    steps = [
      %{
        verdict: "pass",
        results: [
          %{member: "Alice", verdict: "fail"},
          %{member: "Bob", verdict: "pass"}
        ]
      }
    ]

    TrustScorer.record_run(steps)
    # Give the async task time to complete in test
    Process.sleep(50)

    scores = TrustScorer.list_scores()
    alice = Enum.find(scores, &(&1.member_name == "Alice"))
    bob = Enum.find(scores, &(&1.member_name == "Bob"))

    assert alice != nil
    assert alice.decay_count == 1
    assert bob == nil
  end
end
```

**Step 4: Run to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/trust_scorer_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: `ExCortex.TrustScorer is not loaded`

**Step 5: Create schema**

```elixir
# lib/ex_cortex/trust/member_trust_score.ex
defmodule ExCortex.Trust.MemberTrustScore do
  use Ecto.Schema
  import Ecto.Changeset

  schema "member_trust_scores" do
    field :member_name, :string
    field :score, :float, default: 1.0
    field :decay_count, :integer, default: 0
    timestamps()
  end

  def changeset(score, attrs) do
    score
    |> cast(attrs, [:member_name, :score, :decay_count])
    |> validate_required([:member_name])
  end
end
```

**Step 6: Create TrustScorer module**

```elixir
# lib/ex_cortex/trust_scorer.ex
defmodule ExCortex.TrustScorer do
  @moduledoc """
  Records member trust scores based on verdict consistency.
  When a member's individual verdict contradicts the aggregated step verdict,
  their score decays by ×0.97.
  """

  import Ecto.Query
  alias ExCortex.Repo
  alias ExCortex.Trust.MemberTrustScore

  require Logger

  @decay_factor 0.97

  @doc "Asynchronously decay scores for members who contradicted their step's verdict."
  def record_run(steps) do
    Task.start(fn ->
      Enum.each(steps, fn step ->
        step_verdict = step.verdict

        Enum.each(step.results || [], fn result ->
          member_name = result[:member] || result.member

          if member_name && result.verdict != step_verdict do
            decay(member_name)
          end
        end)
      end)
    end)
  end

  @doc "Decay a single member's trust score."
  def decay(member_name) do
    now = DateTime.utc_now(:second)

    Repo.insert(
      %MemberTrustScore{member_name: member_name, score: @decay_factor, decay_count: 1, inserted_at: now, updated_at: now},
      on_conflict: [
        set: [
          score: fragment("member_trust_scores.score * ?", @decay_factor),
          decay_count: fragment("member_trust_scores.decay_count + 1"),
          updated_at: ^now
        ]
      ],
      conflict_target: :member_name
    )
  end

  @doc "List all trust scores, ordered by score ascending (least trusted first)."
  def list_scores do
    Repo.all(from s in MemberTrustScore, order_by: [asc: s.score])
  end
end
```

**Step 7: Hook TrustScorer into QuestRunner**

In `lib/ex_cortex/quest_runner.ex`, update the `run/2` clause for plain rosters. After `{:ok, %{verdict: final_verdict || "pass", steps: steps}}` is assembled, call TrustScorer:

Find the `run(roster, input_text) when is_list(roster)` function. At the end, replace the return:

```elixir
result = {:ok, %{verdict: final_verdict || "pass", steps: steps}}
ExCortex.TrustScorer.record_run(steps)
result
```

**Step 8: Run tests**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/trust_scorer_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: All tests pass.

**Step 9: Add Trust panel to Lodge**

In `lib/ex_cortex_web/live/lodge_live.ex`:

1. Add `alias ExCortex.TrustScorer` near the top.

2. In `mount/3`, add:
```elixir
trust_scores = TrustScorer.list_scores()
socket = assign(socket, ..., trust_scores: trust_scores)
```

3. In the render, add a Trust panel (place near DriftMonitor):

```heex
<div class="rounded-lg border bg-card p-4">
  <h3 class="font-semibold mb-3">Member Trust</h3>
  <%= if @trust_scores == [] do %>
    <p class="text-sm text-muted-foreground">No trust data yet — scores appear after quest runs.</p>
  <% else %>
    <table class="w-full text-sm">
      <thead>
        <tr class="text-left text-muted-foreground text-xs border-b">
          <th class="pb-1">Member</th>
          <th class="pb-1">Score</th>
          <th class="pb-1">Decays</th>
        </tr>
      </thead>
      <tbody>
        <%= for score <- @trust_scores do %>
          <tr class="border-b last:border-0">
            <td class="py-1"><%= score.member_name %></td>
            <td class="py-1">
              <span class={[
                "font-mono font-medium",
                if(score.score >= 0.9, do: "text-green-600", else: if(score.score >= 0.75, do: "text-yellow-600", else: "text-red-600"))
              ]}>
                <%= Float.round(score.score, 3) %>
              </span>
            </td>
            <td class="py-1 text-muted-foreground"><%= score.decay_count %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% end %>
</div>
```

**Step 10: Run full test suite**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test --seed 0 2>&1 | tail -20' --pane=main:1.3
```

**Step 11: Commit**

```bash
git add priv/repo/migrations/20260309030000_create_member_trust_scores.exs lib/ex_cortex/trust/ lib/ex_cortex/trust_scorer.ex lib/ex_cortex/quest_runner.ex lib/ex_cortex_web/live/lodge_live.ex test/ex_cortex/trust_scorer_test.exs
git commit -m "feat: member trust scoring — decays on verdict contradictions, surfaces in Lodge"
```

---

## Task 8: Guide Page

**Files:**
- Create: `lib/ex_cortex_web/live/guide_live.ex`
- Modify: `lib/ex_cortex_web/router.ex`
- Modify: `lib/ex_cortex_web/components/layouts/root.html.heex`
- Test: `test/ex_cortex_web/live/guide_live_test.exs`

**Background:** A read-only `/guide` LiveView documenting how to use campaigns, branch steps, charter documents, the challenger member, rank gates, model fallback, and trust scoring. Static content — no DB, no assigns beyond what LiveView needs.

**Step 1: Write the failing test**

```elixir
# test/ex_cortex_web/live/guide_live_test.exs
defmodule ExCortexWeb.GuideLiveTest do
  use ExCortexWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders guide page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/guide")
    assert html =~ "Guide"
    assert html =~ "Campaign"
    assert html =~ "Branch"
    assert html =~ "Challenger"
    assert html =~ "Trust"
  end
end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex_web/live/guide_live_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: route not found.

**Step 3: Add route**

In `lib/ex_cortex_web/router.ex`, inside the `live_session :default` block, add:

```elixir
live "/guide", GuideLive, :index
```

**Step 4: Create LiveView**

```elixir
# lib/ex_cortex_web/live/guide_live.ex
defmodule ExCortexWeb.GuideLive do
  use ExCortexWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto py-8 px-4 space-y-10">
      <div>
        <h1 class="text-3xl font-bold mb-1">ExCortex Guide</h1>
        <p class="text-muted-foreground">How to get the most out of quests, campaigns, and guild features.</p>
      </div>

      <section>
        <h2 class="text-xl font-semibold mb-3">Campaigns</h2>
        <p class="text-sm text-muted-foreground mb-3">
          Campaigns chain quests together. Each step's output becomes context for the next step.
          Create a campaign in <.link navigate={~p"/quests"} class="underline">Quests</.link> and add quest steps in order.
        </p>
        <div class="bg-muted rounded p-4 text-xs font-mono whitespace-pre">
    steps:
      - quest_id: "1"
        order: 1
      - quest_id: "2"
        order: 2
        </div>
        <p class="text-sm text-muted-foreground mt-2">
          The second quest receives a structured handoff block: the prior verdict, member findings, and an open question tailored to its domain.
        </p>
      </section>

      <section>
        <h2 class="text-xl font-semibold mb-3">Branch Steps (Parallel Workstreams)</h2>
        <p class="text-sm text-muted-foreground mb-3">
          Branch steps run multiple quests simultaneously and feed all results to a synthesizer quest.
          Use this for independent checks (accuracy, tone, safety) that run in parallel.
        </p>
        <div class="bg-muted rounded p-4 text-xs font-mono whitespace-pre">
    steps:
      - type: branch
        order: 1
        quests:
          - "quest_id_accuracy"
          - "quest_id_tone"
          - "quest_id_safety"
        synthesizer: "quest_id_synthesis"
        </div>
      </section>

      <section>
        <h2 class="text-xl font-semibold mb-3">The Challenger Member</h2>
        <p class="text-sm text-muted-foreground mb-3">
          Add <code class="bg-muted px-1 rounded">who: "challenger"</code> to any roster step to insert a skeptic
          that demands evidence before accepting a pass verdict. Defaults to NEEDS WORK. Useful as a final validation
          step in multi-stage campaigns.
        </p>
        <div class="bg-muted rounded p-4 text-xs font-mono whitespace-pre">
    roster:
      - who: all
        how: consensus
      - who: challenger
        how: solo
        escalate_on:
          type: verdict
          values: [fail]
        </div>
      </section>

      <section>
        <h2 class="text-xl font-semibold mb-3">Rank-Gated Quests</h2>
        <p class="text-sm text-muted-foreground mb-3">
          Set <code class="bg-muted px-1 rounded">min_rank</code> on a quest to prevent it from running unless
          at least one active member meets that rank. Options: <code class="bg-muted px-1 rounded">apprentice</code>,
          <code class="bg-muted px-1 rounded">journeyman</code>, <code class="bg-muted px-1 rounded">master</code>.
        </p>
        <p class="text-sm text-muted-foreground">
          Useful for gating expensive or sensitive quests behind higher-tier models.
          Returns <code class="bg-muted px-1 rounded">{:error, {:rank_insufficient, reason}}</code> if no eligible members exist.
        </p>
      </section>

      <section>
        <h2 class="text-xl font-semibold mb-3">Guild Charter Documents</h2>
        <p class="text-sm text-muted-foreground mb-3">
          Each guild can have a charter — shared values, domain rules, output format expectations —
          that gets prepended to every member's context during evaluation.
          Edit charters in <.link navigate={~p"/guild-hall"} class="underline">Guild Hall</.link> on each guild card.
        </p>
        <p class="text-sm text-muted-foreground">
          To inject a charter into a quest, add a <code class="bg-muted px-1 rounded">guild_charter</code>
          context provider with <code class="bg-muted px-1 rounded">guild_name</code> set to the guild's name.
        </p>
      </section>

      <section>
        <h2 class="text-xl font-semibold mb-3">Model Fallback Chains</h2>
        <p class="text-sm text-muted-foreground mb-3">
          When Ollama fails for a member's assigned model, ExCortex automatically retries with models
          from the configured fallback chain. Configure in <code class="bg-muted px-1 rounded">config/config.exs</code>:
        </p>
        <div class="bg-muted rounded p-4 text-xs font-mono whitespace-pre">
    config :ex_cortex, :model_fallback_chain, ["phi4-mini", "gemma3:4b", "llama3:8b"]
        </div>
        <p class="text-sm text-muted-foreground mt-2">
          The assigned model is tried first. If it fails, models from the chain are tried in order.
          If all fail, the member abstains.
        </p>
      </section>

      <section>
        <h2 class="text-xl font-semibold mb-3">Member Trust Scores</h2>
        <p class="text-sm text-muted-foreground mb-3">
          After each quest run, members whose individual verdict contradicts the aggregated step verdict
          have their trust score decayed (×0.97). Scores start at 1.0 and are visible in the
          <.link navigate={~p"/lodge"} class="underline">Lodge</.link> under "Member Trust".
        </p>
        <p class="text-sm text-muted-foreground">
          Color coding: green ≥ 0.9 · yellow ≥ 0.75 · red below 0.75.
          Use trust scores to identify members whose judgement consistently diverges from consensus.
        </p>
      </section>
    </div>
    """
  end
end
```

**Step 5: Add nav link**

In `lib/ex_cortex_web/components/layouts/root.html.heex`, find the nav links list and add `"Guide"`:

```elixir
{"Guide", ~p"/guide"},
```

Place it after `{"Quest Board", ~p"/quest-board"}`.

**Step 6: Run tests**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex_web/live/guide_live_test.exs --seed 0 2>&1 | tail -20' --pane=main:1.3
```

Expected: All tests pass.

**Step 7: Run full suite**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test --seed 0 2>&1 | tail -20' --pane=main:1.3
```

**Step 8: Commit**

```bash
git add lib/ex_cortex_web/live/guide_live.ex lib/ex_cortex_web/router.ex lib/ex_cortex_web/components/layouts/root.html.heex test/ex_cortex_web/live/guide_live_test.exs
git commit -m "feat: add /guide page — how-to documentation for campaigns, branch steps, trust scoring, and more"
```

---

## Summary

| Task | Feature | Prereqs |
|------|---------|---------|
| 1 | Model fallback chains | None |
| 2 | Challenger builtin member | None |
| 3 | Rank-gated quest eligibility | None |
| 4 | Structured campaign handoff | Behavioral campaigns plan |
| 5 | Parallel branch steps | Task 4 |
| 6 | Guild charter documents | None |
| 7 | Member trust scoring | None |
| 8 | Guide page | None (but documents all above) |

After all tasks, run:

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test --seed 0 2>&1 | tail -5' --pane=main:1.3
```

Expected: All tests pass with no warnings.
