defmodule ExCortex.DynamicActions.Template do
  @moduledoc "Emergency fallback actions module used when dynamic action creation fails."
  use ExCortex.Core.Actions

  action(:approve, conflicts_with: [:reject])
  action(:reject, conflicts_with: [:approve])
  action(:escalate, orthogonal: true)
end
