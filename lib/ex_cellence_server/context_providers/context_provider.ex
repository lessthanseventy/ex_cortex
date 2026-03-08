defmodule ExCellenceServer.ContextProviders.ContextProvider do
  @moduledoc """
  Behaviour for context providers — modules that supply additional context
  to inject into the prompt preamble before evaluation.

  Each provider receives the quest and input text, and returns a string
  to prepend to the user message.

  ## Provider config map format (stored on Quest)
    %{"type" => "static", "content" => "Always consider..."}
    %{"type" => "quest_history", "limit" => 5}
    %{"type" => "member_stats"}
  """

  @callback build(config :: map(), quest :: map(), input :: String.t()) :: String.t()

  @doc """
  Assemble all context strings from a list of provider configs.
  Returns a single string to prepend, or "" if none.
  """
  def assemble(providers, quest, input) when is_list(providers) do
    providers
    |> Enum.map(&build_one(&1, quest, input))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  def assemble(_, _, _), do: ""

  defp build_one(%{"type" => type} = config, quest, input) do
    mod = module_for(type)

    if mod do
      try do
        apply(mod, :build, [config, quest, input])
      rescue
        _ -> ""
      end
    else
      ""
    end
  end

  defp build_one(_, _, _), do: ""

  defp module_for("static"), do: Module.concat([ExCellenceServer, ContextProviders, Static])

  defp module_for("quest_history"), do: Module.concat([ExCellenceServer, ContextProviders, QuestHistory])

  defp module_for("member_stats"), do: Module.concat([ExCellenceServer, ContextProviders, MemberStats])

  defp module_for(_), do: nil
end
