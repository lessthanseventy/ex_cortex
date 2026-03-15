defmodule ExCortex.Core.Registry.RoleAdapter do
  @moduledoc "Adapts a DB-stored role config to the same interface as a compiled Role module."

  alias ExCortex.Core.Verdict

  def perspectives(config) do
    config
    |> Map.get("perspectives", [])
    |> Enum.map(&String.to_atom(&1["name"]))
  end

  def variant_config(config, variant) do
    variant_str = to_string(variant)

    perspective =
      config
      |> Map.get("perspectives", [])
      |> Enum.find(&(&1["name"] == variant_str))

    %{
      model: perspective["model"],
      strategy: String.to_atom(perspective["strategy"]),
      name: "db.#{variant_str}",
      variant: variant
    }
  end

  def system_prompt(config), do: Map.get(config, "system_prompt", "")

  def build_prompt(config, input) do
    template = Map.get(config, "prompt_template")

    if template && String.contains?(template, "{{input}}") do
      String.replace(template, "{{input}}", inspect(input))
    else
      "#{system_prompt(config)}\n\nEvaluate the following:\n\n#{inspect(input)}"
    end
  end

  def parse_response(_config, text, agent_name, opts) do
    model = Keyword.get(opts, :model, "unknown")
    strategy = Keyword.get(opts, :strategy, :unknown)
    downcased = String.downcase(text)

    {action, confidence, reasoning} =
      cond do
        String.contains?(downcased, "approve") ->
          {:approve, extract_confidence(downcased), extract_reason(text)}

        String.contains?(downcased, "reject") ->
          {:reject, extract_confidence(downcased), extract_reason(text)}

        true ->
          {:abstain, 0.0, "Unparseable response: #{text}"}
      end

    role =
      case String.split(agent_name, ".") do
        [r | _] -> String.to_atom(r)
        _ -> :unknown
      end

    variant =
      case String.split(agent_name, ".") do
        [_ | rest] when rest != [] -> rest |> List.last() |> String.to_atom()
        _ -> :unknown
      end

    Verdict.new(
      role: role,
      variant: variant,
      action: action,
      confidence: confidence,
      reasoning: reasoning,
      model: model,
      strategy: strategy
    )
  end

  defp extract_confidence(text) do
    case Regex.run(~r/confidence:\s*([\d.]+)/i, text) do
      [_, val] ->
        case Float.parse(val) do
          {f, _} when f >= 0 and f <= 1 -> f
          _ -> 0.5
        end

      nil ->
        0.5
    end
  end

  defp extract_reason(text) do
    case Regex.run(~r/reason:\s*(.+)/i, text) do
      [_, reason] -> String.trim(reason)
      nil -> text
    end
  end
end
