defmodule ExCortex.ContextProviders.AgentsMd do
  @moduledoc false
  @behaviour ExCortex.ContextProviders.ContextProvider

  @impl true
  def build(%{"repo_path" => repo_path} = config, _thought, _input) do
    filename = config["filename"] || "AGENTS.md"
    path = Path.join(repo_path, filename)

    case File.read(path) do
      {:ok, content} when content != "" ->
        """
        <agents_md source="#{filename}">
        #{String.trim(content)}
        </agents_md>
        """

      _ ->
        ""
    end
  end

  def build(_, _, _), do: ""
end
