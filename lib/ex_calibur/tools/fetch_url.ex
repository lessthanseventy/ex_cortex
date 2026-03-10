defmodule ExCalibur.Tools.FetchUrl do
  @moduledoc "Tool (YOLO): fetch the body of a URL."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "fetch_url",
      description: "Fetch the text content of a URL. Only use when explicitly permitted.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "url" => %{"type" => "string", "description" => "The URL to fetch"}
        },
        "required" => ["url"]
      },
      callback: &call/1
    )
  end

  def call(%{"url" => url}) do
    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, String.slice(body, 0, 4000)}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end
end
