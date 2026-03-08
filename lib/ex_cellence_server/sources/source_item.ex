defmodule ExCellenceServer.Sources.SourceItem do
  @moduledoc false
  @type t :: %__MODULE__{
          source_id: String.t(),
          type: String.t(),
          content: String.t(),
          metadata: map()
        }

  defstruct [:source_id, :type, :content, :metadata]
end
