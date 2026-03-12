defmodule Overmind.Ritual.Scheduler do
  @moduledoc false
  use GenServer

  # Check every 60 seconds whether any ritual is due
  @tick_ms 60_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  # Returns true if the cron expression matches the given DateTime.
  # Format: "minute hour dom month dow" — each field is "*" or an integer.
  # Exposed as public for unit testing without starting the GenServer.
  @spec cron_matches?(String.t(), DateTime.t()) :: boolean()
  def cron_matches?(expr, datetime) do
    case String.split(expr) do
      [min, hour, dom, month, dow] ->
        field_matches?(min, datetime.minute) and
          field_matches?(hour, datetime.hour) and
          field_matches?(dom, datetime.day) and
          field_matches?(month, datetime.month) and
          field_matches?(dow, day_of_week(datetime))

      _ ->
        false
    end
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule_tick()
    run_due_rituals()
    {:noreply, state}
  end

  # Private

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp run_due_rituals do
    now = DateTime.utc_now()

    Overmind.Ritual.list()
    |> Enum.filter(&cron_matches?(&1.cron_expr, now))
    |> Enum.each(&spawn_ritual/1)
  end

  defp spawn_ritual(%{id: id, name: name, command: command}) do
    now_ts = System.system_time(:second)
    Overmind.Ritual.update_last_run(id, now_ts)
    quest_name = "#{name}-#{now_ts}"
    Overmind.Quest.run(quest_name, command)
  end

  # Standard cron DOW: 0=Sunday, 1=Monday, ..., 6=Saturday
  # Date.day_of_week(:monday) returns Monday=1..Saturday=6, Sunday=7
  # rem(7, 7) = 0 maps Sunday to 0, others stay as-is.
  defp day_of_week(datetime) do
    Date.day_of_week(datetime, :monday) |> rem(7)
  end

  defp field_matches?("*", _), do: true

  defp field_matches?(val, actual) do
    case Integer.parse(val) do
      {n, ""} -> n == actual
      _ -> false
    end
  end
end
