defmodule ExCortexWeb.ExpressionReplyController do
  use ExCortexWeb, :controller

  import Ecto.Query

  alias ExCortex.Expressions.Correlation
  alias ExCortex.Repo

  def reply(conn, %{"ref" => ref, "content" => content}) when is_binary(ref) do
    case Repo.one(from(c in Correlation, where: c.external_ref == ^ref)) do
      nil ->
        conn |> put_status(404) |> json(%{error: "correlation not found"})

      %{daydream_id: daydream_id} ->
        daydream = Repo.get(ExCortex.Ruminations.Daydream, daydream_id)

        if daydream && daydream.status == "running" do
          Phoenix.PubSub.broadcast(
            ExCortex.PubSub,
            "daydream:#{daydream_id}:inbox",
            {:inbox_message,
             %{
               from: "expression_reply",
               content: content,
               timestamp: DateTime.utc_now(),
               correlation_id: ref
             }}
          )

          json(conn, %{status: "delivered", daydream_id: daydream_id})
        else
          status = if daydream, do: daydream.status, else: "not_found"
          json(conn, %{status: "accepted", note: "daydream #{status}"})
        end
    end
  end

  def reply(conn, %{"content" => _}) do
    conn |> put_status(400) |> json(%{error: "missing ref parameter"})
  end

  def reply(conn, _) do
    conn |> put_status(400) |> json(%{error: "missing content and ref parameters"})
  end
end
