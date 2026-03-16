defmodule ExCortex.Tools.FetchUrl do
  @moduledoc "Tool (YOLO): fetch the body of a URL."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "fetch_url",
      description:
        "Fetch raw content from a URL (HTML, JSON, plain text). Returns up to 4000 characters. Use web_fetch instead for human-readable web pages. Use this for APIs or raw data. Example: fetch_url(url: \"https://api.example.com/data.json\")",
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
