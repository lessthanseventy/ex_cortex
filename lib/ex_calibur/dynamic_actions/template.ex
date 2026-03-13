defmodule ExCalibur.DynamicActions.Template do
  @moduledoc "Emergency fallback actions module used when dynamic action creation fails."
  use ExCalibur.Agent.Actions

  action(:approve, conflicts_with: [:reject])
  action(:reject, conflicts_with: [:approve])
  action(:escalate, orthogonal: true)
end
