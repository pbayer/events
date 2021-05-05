defmodule Events.Clock do
  @moduledoc """
  `Events.Clock` defines a virtual clock for executing events on
  a virtual time line. An event is a list of functions to execute
  at a virtual time `t`.

  A clock is started as an Elixir process that registers events
  on its timeline and can execute those events stepwise or for a
  given time interval.

  The events (functions) get/take the clock `pid` as their first
  argument and therefore may register further events on the
  clock's timeline and therefore cause a cascade of events.
  """

  alias Events.PQ

  @doc """
  Start a new clock with an empty event queue and a start time `t0`.
  Return the `pid`.
  """
  @spec new(number) :: pid
  def new(t0 \\ 0) do
    client = self()
    spawn(Events.Clock, :idle_clock, [t0, PQ.new(),
          %{evcount: 0, state: :idle, tend: t0, client: client}]
         )
  end

  def event(clk, f, :at, t, c), do: send clk, {:event, f, :at, t, c}
  def event(clk, f, :after, t, c), do: send clk, {:event, f, :after, t, c}

  def run(clk, t), do: send clk, {:run, self(), t}
  def runs(clk, t) do
    run(clk, t)
    receive do
      {:ok, msg} -> msg
    end
  end

  def query(clk, item), do: send clk, {:query, item, self()}
  def querys(clk, item) do
    query(clk, item)
    receive do
      ans -> ans
    end
  end

  def idle_clock(t, pq, s) do
    receive do
      {:event, f, timing, te, cy} ->
        pq = add_event(f, timing, te, t, cy, pq)
        idle_clock(t, pq, s)
      {:query, item, client} ->
          query_clock(item, client, t, pq, s)
          idle_clock(t, pq, s)
      {:run, client, tr} ->
        running_clock(t, pq, %{s | evcount: 0, state: :running, tend: t+tr, client: client})
      {:step, client} ->
        {t, pq} = PQ.next(self(), pq)
        send client, {:ok, %{events: s.evcount + 1, time: t}}
        idle_clock(t, pq, %{s | evcount: s.evcount + 1})
      msg ->
        IO.puts "Clock #{self()} undefined message #{msg}"
        idle_clock(t, pq, s)
    end
  end

  def running_clock(t, pq, s) do
    receive do
      {:event, f, timing, te, cy} ->
        pq = add_event(f, timing, te, t, cy, pq)
        running_clock(t, pq, s)
      {:query, item, client} ->
        query_clock(item, client, t, pq, s)
        running_clock(t, pq, s)
      {:stop, client} ->
        send client, {:stopped, %{events: s.evcount, time: t}}
        idle_clock(t, pq, %{s | state: :idle})
      {:finish} ->
        send s.client, {:done, %{events: s.evcount, time: t}}
        idle_clock(t, pq, %{s | state: :idle})
      msg ->
        IO.puts "Clock #{self()} undefined message #{msg}"
        running_clock(t, pq, s)
    after 0 ->
      {t, pq} = PQ.next(self(), pq)
      if pq == nil do
        send self(), {:finish}
      end
      running_clock(t, pq, %{s | evcount: s.evcount + 1})
    end
  end

  defp add_event(f, :at, te, _, cy, pq), do: PQ.add(f, te, cy, pq)
  defp add_event(f, :after, te, t, cy, pq), do: PQ.add(f, t+te, cy, pq)

  defp query_clock(:now, client, t, _, _), do: send client, {:time, t}
  defp query_clock(:events, client, _, pq, _), do: send client, {:events, pq}
  defp query_clock(:state, client, _, _, s), do: send client, {:state, s}

end
