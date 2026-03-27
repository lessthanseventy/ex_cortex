defmodule ExCortex.Ruminations.Middleware.Scratchpad do
  @moduledoc """
  Opt-in middleware that persists a scratchpad across impulses within a daydream.

  Enable by adding "Elixir.ExCortex.Ruminations.Middleware.Scratchpad" to a
  synapse's middleware list.

  - before_impulse: Prepends current scratchpad contents to input_text.
  - after_impulse: Parses SCRATCHPAD: ... END_SCRATCHPAD blocks from the result,
    merges them into the daydream's scratchpad, persists to DB, strips the block
    from the result.
  - wrap_tool_call: Pass-through.
  """
  @behaviour ExCortex.Ruminations.Middleware

  alias ExCortex.Repo
  alias ExCortex.Ruminations.Middleware.Context

  require Logger

  @impl true
  def before_impulse(%Context{daydream: daydream} = ctx, _opts) do
    scratchpad = (daydream && daydream.scratchpad) || %{}

    ctx =
      if map_size(scratchpad) > 0 do
        formatted =
          Enum.map_join(scratchpad, "\n", fn {k, v} -> "#{k}: #{v}" end)

        prefix = "## Scratchpad\n#{formatted}\n\n"
        %{ctx | input_text: prefix <> (ctx.input_text || ""), metadata: Map.put(ctx.metadata, :scratchpad, scratchpad)}
      else
        %{ctx | metadata: Map.put(ctx.metadata, :scratchpad, scratchpad)}
      end

    {:cont, ctx}
  end

  @impl true
  def after_impulse(%Context{daydream: daydream} = ctx, result, _opts) do
    with true <- is_binary(result),
         {parsed, stripped} <- extract_scratchpad(result),
         true <- map_size(parsed) > 0 do
      existing = (daydream && daydream.scratchpad) || %{}
      updated = Map.merge(existing, parsed)
      persist_scratchpad(daydream, updated)
      _ = ctx
      stripped
    else
      _ -> result
    end
  end

  @impl true
  def wrap_tool_call(_tool_name, _tool_args, execute_fn), do: execute_fn.()

  # ── Private ────────────────────────────────────────────────────────────────

  defp extract_scratchpad(text) do
    case Regex.run(~r/SCRATCHPAD:(.*?)END_SCRATCHPAD/s, text, capture: :all) do
      [full_match, block] ->
        parsed = parse_kv_block(block)
        stripped = text |> String.replace(full_match, "") |> String.trim()
        {parsed, stripped}

      nil ->
        {%{}, text}
    end
  end

  defp parse_kv_block(block) do
    block
    |> String.split("\n")
    |> Enum.reduce(%{}, &parse_kv_line/2)
  end

  defp parse_kv_line(line, acc) do
    case String.split(line, ":", parts: 2) do
      [key, value] ->
        k = String.trim(key)
        v = String.trim(value)
        if k == "", do: acc, else: Map.put(acc, k, v)

      _ ->
        acc
    end
  end

  defp persist_scratchpad(nil, _updated), do: :ok

  defp persist_scratchpad(daydream, updated) do
    changeset = Ecto.Changeset.change(daydream, scratchpad: updated)

    case Repo.update(changeset) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Scratchpad] Failed to persist scratchpad: #{inspect(reason)}")
    end
  end
end
