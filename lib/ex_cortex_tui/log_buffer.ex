defmodule ExCortexTUI.LogBuffer do
  @moduledoc "Ring buffer for capturing log messages in TUI mode."
  use GenServer

  @max_lines 200

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_lines(count \\ 50) do
    GenServer.call(__MODULE__, {:get, count})
  end

  def append(line) do
    GenServer.cast(__MODULE__, {:append, line})
  end

  @impl true
  def init(_opts) do
    {:ok, :queue.new()}
  end

  @impl true
  def handle_call({:get, count}, _from, queue) do
    lines = :queue.to_list(queue)
    {:reply, Enum.take(lines, -count), queue}
  end

  @impl true
  def handle_cast({:append, line}, queue) do
    queue = :queue.in(line, queue)

    queue =
      if :queue.len(queue) > @max_lines do
        {_, q} = :queue.out(queue)
        q
      else
        queue
      end

    {:noreply, queue}
  end
end
