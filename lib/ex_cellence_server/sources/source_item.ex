defmodule ExCellenceServer.Sources.SourceItem do
  @moduledoc false
  @type t :: %__MODULE__{
          source_id: String.t(),
          guild_name: String.t(),
          type: String.t(),
          content: String.t(),
          metadata: map()
        }

  defstruct [:source_id, :guild_name, :type, :content, :metadata]
end
