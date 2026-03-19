defmodule ExCortex.Ruminations.ImpulseRunner.Artifact do
  @moduledoc false

  alias ExCortex.Ruminations.RosterResolver

  @valid_card_types ~w(note checklist meeting alert link briefing action_list table media metric freeform)

  def post_signal_cards(thought, attrs) do
    cards_spec = Map.get(thought, :cards) || %{}

    if cards_spec == %{} do
      post_single_signal_card(thought, attrs)
    else
      post_multi_signal_cards(thought, attrs, cards_spec)
    end
  end

  def post_single_signal_card(thought, attrs) do
    card_type = attrs[:card_type] || parse_card_type(thought.description) || "note"

    # Build action_handler for interactive pane features
    base_metadata = attrs[:metadata] || %{}

    metadata =
      if Map.get(thought, :rumination_id) || Map.get(thought, :id) do
        rum_id = Map.get(thought, :rumination_id) || Map.get(thought, :id)

        action_handler =
          base_metadata
          |> Map.get("action_handler", %{})
          |> Map.put_new("refresh", %{"rumination_id" => rum_id})

        Map.put(base_metadata, "action_handler", action_handler)
      else
        base_metadata
      end

    card_attrs = %{
      type: card_type,
      card_type: card_type,
      title: attrs.title,
      body: attrs.body,
      tags: attrs[:tags] |> Kernel.||([]) |> Enum.uniq() |> Enum.take(15),
      source: "rumination",
      rumination_id: thought.id,
      metadata: metadata,
      pin_slug: Map.get(thought, :pin_slug),
      pinned: Map.get(thought, :pin_slug) != nil || Map.get(thought, :pinned, false),
      pin_order: Map.get(thought, :pin_order, 0),
      cluster_name: Map.get(thought, :cluster_name)
    }

    ExCortex.Signals.post_signal(card_attrs)
    {:ok, %{signal: card_attrs}}
  end

  def post_multi_signal_cards(thought, attrs, cards_spec) do
    posted =
      Enum.map(cards_spec, fn spec ->
        card_attrs = %{
          type: spec["card_type"] || "briefing",
          card_type: spec["card_type"] || "briefing",
          title: attrs.title,
          body: attrs.body,
          tags: attrs[:tags] |> Kernel.||([]) |> Enum.uniq() |> Enum.take(15),
          source: "rumination",
          rumination_id: thought.id,
          metadata: attrs[:metadata] || %{},
          pin_slug: spec["pin_slug"],
          pinned: spec["pinned"] || false,
          pin_order: spec["pin_order"] || 0,
          cluster_name: Map.get(thought, :cluster_name)
        }

        ExCortex.Signals.post_signal(card_attrs)
      end)

    {:ok, %{signals: posted}}
  end

  def run_artifact(thought, input_text) do
    roster = thought.roster || []

    case roster do
      [] ->
        {:error, :no_roster}

      [single_step] ->
        # Single step — original behaviour
        run_artifact_step(single_step, input_text, thought)

      steps ->
        # Multi-step: run all but last in reasoning mode, thread outputs to final step
        {prelim_steps, [final_step]} = Enum.split(steps, length(steps) - 1)
        reasoning_context = build_reasoning_context(prelim_steps, input_text)
        augmented = "#{input_text}\n\n---\n## Team Analysis\n#{reasoning_context}"
        run_artifact_step(final_step, augmented, thought)
    end
  end

  def run_artifact_step(step, input_text, thought) do
    neurons = RosterResolver.resolve(step)
    neuron = List.first(neurons)

    if is_nil(neuron) do
      {:error, :no_members}
    else
      system_prompt = artifact_system_prompt(thought)

      raw =
        case ExCortex.LLM.complete(neuron.provider, neuron.model, system_prompt, input_text) do
          {:ok, text} -> text
          _ -> nil
        end

      if raw do
        date = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")
        title_template = thought.entry_title_template || thought.name || "Entry — {date}"
        title = String.replace(title_template, "{date}", date)
        {:ok, parse_artifact(raw, title)}
      else
        {:error, :llm_failed}
      end
    end
  end

  def build_reasoning_context(prelim_steps, input_text) do
    Enum.map_join(prelim_steps, "\n\n", fn step ->
      label = step["label"] || step["who"] || "Analyst"
      member_outputs = build_step_member_outputs(step, input_text)
      "### #{label}\n#{member_outputs}"
    end)
  end

  def build_step_member_outputs(step, input_text) do
    neurons = RosterResolver.resolve(step)

    Enum.map_join(neurons, "\n\n", fn neuron ->
      reasoning_prompt = reasoning_system_prompt(neuron, step)

      text =
        case ExCortex.LLM.complete(neuron.provider, neuron.model, reasoning_prompt, input_text) do
          {:ok, t} -> t
          _ -> "(no response)"
        end

      "**#{neuron.name}:** #{String.slice(text, 0, 500)}"
    end)
  end

  def reasoning_system_prompt(neuron, step) do
    base = neuron.system_prompt || ""
    label = step["label"] || neuron.name

    lobe_prefix =
      case ExCortex.Lobe.prompt_for_cluster(step["cluster_name"] || neuron.team) do
        nil -> ""
        prompt -> "[#{prompt}]\n\n"
      end

    """
    #{lobe_prefix}#{base}

    You are #{label}. Provide your analysis and perspective on the data below.
    Be direct and opinionated. Your output will be read by a synthesizer.
    Do NOT use the TITLE/IMPORTANCE/TAGS/BODY format — just write your raw analysis.
    """
  end

  def artifact_system_prompt(thought) do
    instruction = thought.description || "Synthesize the provided content."
    today = Calendar.strftime(Date.utc_today(), "%B %d, %Y")

    """
    Today's date is #{today}.

    #{instruction}

    Respond in this exact format:
    TITLE: <a concise title for this entry>
    IMPORTANCE: <integer 1-5, where 5 is most important, or omit if not applicable>
    TAGS: <comma-separated tags, lowercase, e.g. a11y,security,deps>
    BODY:
    <your synthesized content here, markdown is fine>
    """
  end

  def parse_artifact(text, fallback_title) do
    %{
      title: parse_artifact_title(text, fallback_title),
      body: parse_artifact_body(text),
      tags: parse_artifact_tags(text),
      importance: parse_artifact_importance(text),
      card_type: parse_artifact_card_type(text),
      source: "step"
    }
  end

  def parse_card_type(nil), do: nil
  def parse_card_type(""), do: nil

  def parse_card_type(description) when is_binary(description) do
    desc = String.downcase(description)
    Enum.find(@valid_card_types, fn type -> String.contains?(desc, type) end)
  end

  # -- Private parse helpers --------------------------------------------------

  defp parse_artifact_title(text, fallback_title) do
    case Regex.run(~r/^TITLE:\s*(.+)$/m, text) do
      [_, t] -> String.trim(t)
      _ -> fallback_title
    end
  end

  defp parse_artifact_importance(text) do
    case Regex.run(~r/^IMPORTANCE:\s*(\d)$/m, text) do
      [_, n] ->
        val = String.to_integer(n)
        if val in 1..5, do: val

      _ ->
        nil
    end
  end

  defp parse_artifact_tags(text) do
    case Regex.run(~r/^TAGS:\s*(.+)$/m, text) do
      [_, t] -> t |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
      _ -> []
    end
  end

  defp parse_artifact_body(text) do
    case Regex.run(~r/^BODY:\s*\n(.*)/ms, text) do
      [_, b] -> String.trim(b)
      _ -> text
    end
  end

  defp parse_artifact_card_type(text) do
    case Regex.run(~r/^CARD_TYPE:\s*(.+)$/m, text) do
      [_, ct] ->
        ct = ct |> String.trim() |> String.downcase()
        if ct in @valid_card_types, do: ct

      _ ->
        nil
    end
  end
end
