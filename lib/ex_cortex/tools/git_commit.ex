defmodule ExCortex.Tools.GitCommit do
  @moduledoc "Tool: stage files and create a git commit in the working directory."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "git_commit",
      description:
        "Stage specific files and create a git commit. REQUIRED: pass working_dir as the worktree path returned by setup_worktree so commits go to the branch, not main.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "files" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Files to stage (relative paths)"
          },
          "message" => %{"type" => "string", "description" => "Commit message"},
          "working_dir" => %{
            "type" => "string",
            "description" => "Absolute path to the worktree directory (from setup_worktree)"
          },
          "trailers" => %{
            "type" => "object",
            "description" => "Optional structured commit trailers. Only include keys with values.",
            "properties" => %{
              "Constraint" => %{"type" => "string", "description" => "What shaped the decision"},
              "Rejected" => %{
                "type" => "string",
                "description" => "Alternative considered | why rejected"
              },
              "Confidence" => %{
                "type" => "string",
                "enum" => ["high", "medium", "low"],
                "description" => "Confidence in the approach"
              },
              "Scope-risk" => %{
                "type" => "string",
                "enum" => ["narrow", "moderate", "broad"],
                "description" => "Blast radius of this change"
              },
              "Not-tested" => %{"type" => "string", "description" => "Uncovered edge case"}
            }
          }
        },
        "required" => ["files", "message", "working_dir"]
      },
      callback: &call/1
    )
  end

  def call(%{"files" => files, "message" => message} = params) do
    working_dir = Map.get(params, "working_dir") || File.cwd!()

    Enum.each(files, fn file ->
      System.cmd("git", ["add", file], cd: working_dir, stderr_to_stdout: true)
    end)

    # Styler guard: auto-format staged Elixir files before committing
    elixir_files =
      Enum.filter(files, &(String.ends_with?(&1, ".ex") or String.ends_with?(&1, ".exs")))

    if elixir_files != [] do
      System.cmd("mix", ["format" | elixir_files], cd: working_dir, stderr_to_stdout: true)

      # Re-stage formatted files
      Enum.each(elixir_files, fn file ->
        System.cmd("git", ["add", file], cd: working_dir, stderr_to_stdout: true)
      end)
    end

    # Parse and strip TRAILERS block from commit message, if present
    {clean_message, embedded_trailers} = extract_trailers_block(message)

    # Merge trailers: embedded from message body + explicit map parameter (param wins on collision)
    param_trailers = Map.get(params, "trailers", %{})
    all_trailers = Map.merge(embedded_trailers, param_trailers)

    trailer_lines =
      Enum.map_join(all_trailers, "\n", fn {key, value} -> "#{key}: #{value}" end)

    co_author = "Co-Authored-By: ExCortex Dev Team <devteam@excalibur.local>"

    full_message =
      if trailer_lines == "" do
        clean_message <> "\n\n" <> co_author
      else
        clean_message <> "\n\n" <> co_author <> "\n" <> trailer_lines
      end

    args = [
      "commit",
      "--author=ExCortex Dev Team <devteam@excalibur.local>",
      "-m",
      full_message
    ]

    case System.cmd("git", args, cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Committed: #{String.trim(output)}"}
      {output, _} -> {:error, "Commit failed: #{output}"}
    end
  end

  # Parses and strips a TRAILERS:...END_TRAILERS block from the commit message.
  # Returns {cleaned_message, trailer_map}.
  defp extract_trailers_block(message) do
    trailers_marker = "\nTRAILERS:\n"
    end_marker = "\nEND_TRAILERS"

    case :binary.match(message, trailers_marker) do
      :nomatch ->
        {message, %{}}

      {start_idx, marker_len} ->
        block_start = start_idx + marker_len
        rest = binary_part(message, block_start, byte_size(message) - block_start)

        case :binary.match(rest, end_marker) do
          :nomatch ->
            {message, %{}}

          {end_idx, _} ->
            block_text = binary_part(rest, 0, end_idx)
            clean_message = message |> binary_part(0, start_idx) |> String.trim_trailing()

            trailers = parse_trailer_lines(block_text)
            {clean_message, trailers}
        end
    end
  end

  defp parse_trailer_lines(block_text) do
    block_text
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ": ", parts: 2) do
        [key, value] when key != "" -> Map.put(acc, String.trim(key), String.trim(value))
        _ -> acc
      end
    end)
  end
end
