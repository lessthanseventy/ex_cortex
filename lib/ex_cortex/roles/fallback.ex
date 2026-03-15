defmodule ExCortex.Roles.Fallback do
  @moduledoc "Emergency fallback role used when dynamic role creation fails."
  use ExCortex.Core.Role

  system_prompt(
    "Emergency fallback evaluator. Respond: ACTION: reject\nCONFIDENCE: 0.1\nREASON: Dynamic role creation failed, defaulting to reject."
  )

  perspective(:default, model: "ministral-3:8b", strategy: :cot, name: "fallback.default")

  @impl true
  def build_prompt(input, _context), do: "Evaluate: #{inspect(input)}"
end
