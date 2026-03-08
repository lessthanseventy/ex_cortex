defmodule ExCellenceServerWeb.WebhookController do
  use ExCellenceServerWeb, :controller

  alias ExCellenceServer.Evaluator
  alias ExCellenceServer.Sources.Source

  def receive(conn, %{"source_id" => source_id}) do
    with %Source{status: "active", source_type: "webhook"} = source <-
           ExCellenceServer.Repo.get(Source, source_id),
         true <- valid_token?(conn, source) do
      body = conn.body_params["content"] || Jason.encode!(conn.body_params)

      Task.Supervisor.start_child(ExCellenceServer.SourceTaskSupervisor, fn ->
        Evaluator.evaluate(source.guild_name, body)
      end)

      source |> Source.changeset(%{last_run_at: DateTime.utc_now()}) |> ExCellenceServer.Repo.update()
      json(conn, %{status: "accepted"})
    else
      nil -> conn |> put_status(404) |> json(%{error: "source not found"})
      false -> conn |> put_status(401) |> json(%{error: "unauthorized"})
    end
  end

  defp valid_token?(conn, source) do
    expected = get_in(source.config, ["auth_token"])

    if expected do
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> Plug.Crypto.secure_compare(token, expected)
        _ -> false
      end
    else
      true
    end
  end
end
