defmodule ExCalibur.Agent.Verdict do
  @moduledoc "Universal decision container for agent verdicts."

  @enforce_keys [:role, :variant, :action, :confidence, :reasoning, :model, :strategy]
  defstruct [
    :role,
    :variant,
    :action,
    :confidence,
    :reasoning,
    :model,
    :strategy,
    :latency_ms,
    artifacts: %{},
    flags: []
  ]

  @type t :: %__MODULE__{
          role: atom(),
          variant: atom(),
          action: atom(),
          confidence: float(),
          reasoning: String.t(),
          model: String.t(),
          strategy: atom(),
          latency_ms: non_neg_integer() | nil,
          artifacts: map(),
          flags: [atom()]
        }

  def new(attrs) when is_list(attrs), do: struct!(__MODULE__, attrs)
  def new(attrs) when is_map(attrs), do: struct!(__MODULE__, attrs)
end
