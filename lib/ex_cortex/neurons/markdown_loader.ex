defmodule ExCortex.Neurons.MarkdownLoader do
  @moduledoc "Loads neuron definitions from *.md files in priv/neurons/."

  alias ExCortex.Neurons.Builtin

  def load_all do
    dir = Application.app_dir(:ex_cortex, "priv/neurons")

    case File.ls(dir) do
      {:error, _} ->
        []

      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.flat_map(&try_load_file(dir, &1))
    end
  end

  defp try_load_file(dir, name) do
    case load_file(Path.join(dir, name)) do
      {:ok, neuron} -> [neuron]
      _ -> []
    end
  end

  defp load_file(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      _ -> {:error, :unreadable}
    end
  end

  defp parse(content) do
    case String.split(content, ~r/^---[ \t]*$/m, parts: 3) do
      [_, frontmatter, body] ->
        with {:ok, attrs} <- parse_frontmatter(frontmatter) do
          Builtin.from_markdown(attrs, String.trim(body))
        end

      _ ->
        {:error, :no_frontmatter}
    end
  end

  defp parse_frontmatter(text) do
    attrs =
      text
      |> String.split("\n")
      |> parse_lines(%{}, nil)

    {:ok, attrs}
  end

  # Accumulates frontmatter key/value pairs, handling the nested ranks block.
  defp parse_lines([], attrs, _ctx), do: attrs

  defp parse_lines([line | rest], attrs, :ranks) do
    trimmed = String.trim_leading(line)

    cond do
      trimmed == "" ->
        parse_lines(rest, attrs, :ranks)

      String.length(line) - String.length(trimmed) > 0 ->
        # Indented rank line: "  apprentice: {model: ..., strategy: ...}"
        case String.split(trimmed, ": ", parts: 2) do
          [rank_name, inline] ->
            rank_map = parse_inline_map(inline)
            rank_atom = String.to_atom(String.trim(rank_name))
            updated = Map.update(attrs, :ranks, %{rank_atom => rank_map}, &Map.put(&1, rank_atom, rank_map))
            parse_lines(rest, updated, :ranks)

          _ ->
            parse_lines(rest, attrs, :ranks)
        end

      true ->
        # No longer indented — fall back to top-level
        parse_lines([line | rest], attrs, nil)
    end
  end

  defp parse_lines([line | rest], attrs, _ctx) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        parse_lines(rest, attrs, nil)

      trimmed == "ranks:" ->
        parse_lines(rest, attrs, :ranks)

      true ->
        case String.split(trimmed, ": ", parts: 2) do
          [key, value] -> parse_lines(rest, Map.put(attrs, key, String.trim(value)), nil)
          _ -> parse_lines(rest, attrs, nil)
        end
    end
  end

  # Parses {model: "ministral-3:8b", strategy: "cot"} into %{model: "...", strategy: "..."}
  defp parse_inline_map(text) do
    text
    |> String.trim()
    |> String.trim_leading("{")
    |> String.trim_trailing("}")
    |> String.split(",")
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(String.trim(pair), ": ", parts: 2) do
        [k, v] ->
          key = k |> String.trim() |> String.to_atom()
          val = v |> String.trim() |> String.trim("\"")
          Map.put(acc, key, val)

        _ ->
          acc
      end
    end)
  end
end
