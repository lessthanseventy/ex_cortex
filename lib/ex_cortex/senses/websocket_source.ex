defmodule ExCortex.Senses.WebSocketSource do
  @moduledoc false
  @behaviour ExCortex.Senses.Behaviour

  alias ExCortex.Senses.Item

  @impl true
  def init(config) do
    {:ok, %{message_path: config["message_path"], buffer: []}}
  end

  @impl true
  def fetch(state, config) do
    url = config["url"]
    timeout = config["fetch_timeout"] || 5_000

    {:ok, messages} = connect_and_collect(url, state.message_path, timeout)

    items =
      Enum.map(messages, fn msg ->
        %Item{
          source_id: config["source_id"],
          type: "ws_message",
          content: msg,
          metadata: %{url: url}
        }
      end)

    {:ok, items, state}
  end

  defp connect_and_collect(url, message_path, timeout) do
    parent = self()
    ref = make_ref()

    task =
      Task.async(fn ->
        case Fresh.start_link(url, __MODULE__.Handler, %{parent: parent, ref: ref, message_path: message_path}, []) do
          {:ok, pid} ->
            Process.sleep(timeout)
            Process.exit(pid, :normal)

          {:error, reason} ->
            send(parent, {ref, :error, reason})
        end
      end)

    messages = collect_messages(ref, [], timeout + 1_000)
    Task.shutdown(task, :brutal_kill)
    {:ok, messages}
  end

  defp collect_messages(ref, acc, timeout) do
    receive do
      {^ref, :message, msg} -> collect_messages(ref, [msg | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end

  def extract_content(data, nil), do: data

  def extract_content(data, path) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> extract_content(decoded, path)
      _ -> data
    end
  end

  def extract_content(data, path) when is_map(data) do
    path
    |> String.split(".")
    |> Enum.reduce(data, fn key, acc ->
      case acc do
        %{} -> Map.get(acc, key, "")
        _ -> acc
      end
    end)
    |> case do
      val when is_binary(val) -> val
      val -> inspect(val)
    end
  end

  def extract_content(data, _path), do: inspect(data)

  defmodule Handler do
    @moduledoc false
    use Fresh

    @impl true
    def handle_connect(_status, _headers, state) do
      {:ok, state}
    end

    @impl true
    def handle_in({:text, msg}, state) do
      content = ExCortex.Senses.WebSocketSource.extract_content(msg, state.message_path)
      send(state.parent, {state.ref, :message, content})
      {:ok, state}
    end

    @impl true
    def handle_in(_frame, state) do
      {:ok, state}
    end

    @impl true
    def handle_disconnect(_code, _reason, _state) do
      :close
    end
  end
end
