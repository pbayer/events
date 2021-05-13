defmodule Events.Clock do
  @moduledoc """
  `Events.Clock` defines a virtual clock for executing events on
  a virtual time line. An event is a function to execute at a
  virtual time `t`.

  A clock is an Elixir process that
  - registers events on its timeline and
  - can execute those events stepwise or for a given time interval.

  The events (functions) get/take the clock `pid` as their first
  argument and therefore may register further events on the
  clock's timeline thus causing a cascade of events.
  """
  @typedoc """
  `event` type to communicate t a clock. An event is
  - `f`: a function,
  - `timing`: either `:at` or `:after`,
  - `t`: a time for executing `f`,
  - `c`: `nil` or a cycle time for repeating events.
  """
  @type event :: {
          f :: fun,
          timing :: atom,
          t :: number,
          c :: number
        }

  alias Events.PQ

  @doc """
  Start a new clock with an empty event queue and a start time `t0`.
  Return the `pid`.
  """
  @spec new(number) :: pid
  def new(t0 \\ 0) do
    client = self()

    spawn(Events.Clock, :idle_clock, [
      t0,
      PQ.new(),
      %{evcount: 0, state: :idle, tend: t0, client: client}
    ])
  end

  @doc """
  Schedule a new event to a clock `clk`, get back and return the
  event number.
  """
  @spec event(pid, event) :: {:ok, pos_integer}
  def event(clk, {_f, timing, _t, _c} = evt) when timing in [:at, :after] do
    send(clk, {:event, self(), evt})

    receive do
      {:ok, _no} = msg -> msg
    end
  end

  @doc "Run a clock `clk` synchronously for a time `t`."
  @spec run(pid, number) :: {:done, map}
  def run(clk, t) do
    _run(clk, t)

    receive do
      {:done, msg} -> msg
    end
  end

  @doc "Run a clock `clk` for a time `t`."
  def _run(clk, t), do: send(clk, {:run, self(), t})

  @doc "Get the current `clk` time."
  @spec now(pid) :: number
  def now(clk) do
    {:time, t} = query(clk, :now)
    t
  end

  @doc """
  Query a clock `clk` synchronously for an `item`, one of

  - `:now`: the current clock time `{:time, t}`,
  - `:events`: the current event queue `{:events, eq}`,
  - `:state`: the current clock state `{:state, s}.
  """
  @spec query(pid, atom) :: {atom, any}
  def query(clk, item) do
    _query(clk, item)

    receive do
      msg -> msg
    end
  end

  @doc "Query a clock for an `item` to send it back to `self()`."
  def _query(clk, item), do: send(clk, {:query, self(), item})

  def idle_clock(t, eq, s) do
    receive do
      {:event, client, evt} ->
        eq = add_event(evt, t, eq)
        send(client, {:ok, eq.no})
        idle_clock(t, eq, s)

      {:query, client, item} ->
        query_clock(item, client, t, eq, s)
        idle_clock(t, eq, s)

      {:run, client, tr} ->
        {t, fs, eq} = PQ.next(eq)
        next_event(fs)

        running_clock(t, eq, %{
          s
          | evcount: length(fs),
            state: :running,
            tend: t + tr,
            client: client
        })

      {:step, client} ->
        {t, fs, eq} = PQ.next(eq)
        next_event(fs)

        idle_clock(t, eq, %{
          s
          | evcount: s.evcount + length(fs),
            client: client
        })

      {:next, _} ->
        handle_next(t, eq, s)

      msg ->
        IO.puts("Clock #{self()} undefined message #{msg}")
        idle_clock(t, eq, s)
    end
  end

  def running_clock(t, eq, s) do
    receive do
      {:event, client, evt} ->
        eq = add_event(evt, t, eq)
        send(client, {:ok, eq.no})
        running_clock(t, eq, s)

      {:query, client, item} ->
        query_clock(item, client, t, eq, s)
        running_clock(t, eq, s)

      {:stop, client} ->
        running_clock(t, eq, %{s | state: :stopped, client: client})

      {:next, _} ->
        handle_next(t, eq, s)

      msg ->
        IO.puts("Clock #{self()} undefined message #{msg}")
        running_clock(t, eq, s)
    end
  end

  defp next_event(fs) do
    clk = self()
    Task.start_link(fn -> exec_events(fs, clk) end)
  end

  defp handle_next(t, eq, %{state: :stopped} = s) do
    send(s.client, {:stopped, %{events: s.evcount, time: t}})
    idle_clock(t, eq, %{s | state: :idle})
  end

  defp handle_next(t, eq, %{state: :idle} = s) do
    send(s.client, {:ok, %{events: s.evcount, time: t}})
    idle_clock(t, eq, s)
  end

  defp handle_next(_, eq, s) do
    {t, fs, eq} = PQ.next(eq)
    next_event(fs)
    evcount = s.evcount + length(fs)

    if t >= s.tend || eq.psq == nil do
      t = tadjust(s.tend, t)
      send(s.client, {:done, %{events: evcount, time: t}})
      idle_clock(t, eq, %{s | state: :idle, evcount: evcount})
    else
      running_clock(t, eq, %{s | evcount: evcount})
    end
  end

  defp tadjust(t1, nil), do: t1
  defp tadjust(t1, t2), do: max(t1, t2)

  defp add_event({f, :at, te, cy}, _, eq), do: PQ.add(f, te, cy, eq)
  defp add_event({f, :after, te, cy}, t, eq), do: PQ.add(f, t + te, cy, eq)

  defp query_clock(:now, client, t, _, _), do: send(client, {:time, t})
  defp query_clock(:events, client, _, eq, _), do: send(client, {:events, eq})
  defp query_clock(:state, client, _, _, s), do: send(client, {:state, s})

  defp exec_events([f], clk), do: send(clk, {:next, [f.(clk)]})
  defp exec_events([], clk), do: send(clk, {:next, []})

  defp exec_events(fs, clk) do
    tasks = Enum.map(fs, fn f -> Task.async(fn -> f.(clk) end) end)
    {:next, Task.await_many(tasks)}
  end
end
