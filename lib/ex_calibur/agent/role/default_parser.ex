defmodule ExCalibur.Agent.Role.DefaultParser do
  @moduledoc "Default response parser for roles. Extracts DECISION/CONFIDENCE/REASON."

  alias ExCalibur.Agent.Verdict

  def parse(text, agent_name, role_module, opts) do
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

    role = role_module |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()

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
