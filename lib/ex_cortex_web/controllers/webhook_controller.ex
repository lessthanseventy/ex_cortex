defmodule ExCortexWeb.WebhookController do
  use ExCortexWeb, :controller

  alias ExCortex.Evaluator
  alias ExCortex.Senses.Sense

  def receive(conn, %{"sense_id" => sense_id}) do
    with %Sense{status: "active", source_type: "webhook"} = source <-
           ExCortex.Repo.get(Sense, sense_id),
         true <- valid_token?(conn, source) do
      body = conn.body_params["content"] || Jason.encode!(conn.body_params)

      Task.Supervisor.start_child(ExCortex.SourceTaskSupervisor, fn ->
        Evaluator.evaluate(body, trust_level: "untrusted", source_type: "webhook")
      end)

      source |> Sense.changeset(%{last_run_at: DateTime.utc_now()}) |> ExCortex.Repo.update()
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
