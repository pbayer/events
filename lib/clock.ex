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

  @doc "Tell an idle clock `clk` to take one step forward in time."
  @spec step(pid) :: {:ok, map}
  def step(clk) do
    send(clk, {:step, self()})

    receive do
      {:ok, _} = msg -> msg
    end
  end

  @doc "Run a clock `clk` synchronously for a time `t`."
  @spec run(pid, number) :: {:done, map}
  def run(clk, t) do
    _run(clk, t)

    receive do
      {:done, _} = msg -> msg
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

  @doc "Reset a clock `clk`."
  def reset(clk, t0 \\ 0) do
    send(clk, {:reset, self(), t0})

    receive do
      {:ok} -> :ok
      msg -> msg
    end
  end

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
        t0 = t
        {t, fs, eq} = PQ.next(eq)
        next_event(fs)

        running_clock(t, eq, %{
          s
          | evcount: length(fs),
            state: :running,
            tend: t0 + tr,
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

      {:reset, client, t0} ->
        send(client, {:ok})

        idle_clock(
          t0,
          PQ.new(),
          %{evcount: 0, state: :idle, tend: t0, client: client}
        )

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

  defp next_event([]), do: []

  defp next_event(fs) do
    clk = self()
    Task.start_link(fn -> exec_events(fs, clk) end)
  end

  defp exec_events([f], clk), do: send(clk, {:next, [f.(clk)]})

  defp exec_events(fs, clk) do
    tasks = Enum.map(fs, fn f -> Task.async(fn -> f.(clk) end) end)
    send(clk, {:next, Task.await_many(tasks)})
  end

  defp handle_next(t, eq, %{state: :stopped} = s) do
    send(s.client, {:stopped, %{events: s.evcount, time: t}})
    idle_clock(t, eq, %{s | state: :idle})
  end

  defp handle_next(t, eq, %{state: :idle} = s) do
    send(s.client, {:ok, %{events: s.evcount, time: t}})
    idle_clock(t, eq, s)
  end

  defp handle_next(t, eq, s) do
    if t >= s.tend || eq.psq == nil do
      t = max(s.tend, t)
      send(s.client, {:done, %{events: s.evcount, time: t}})
      idle_clock(t, eq, %{s | state: :idle})
    else
      {t, fs, eq} = PQ.next(eq)
      next_event(fs)
      evcount = s.evcount + length(fs)
      running_clock(t, eq, %{s | evcount: evcount})
    end
  end

  defp add_event({f, :at, te, cy}, _, eq), do: PQ.add(f, te, cy, eq)
  defp add_event({f, :after, te, cy}, t, eq), do: PQ.add(f, t + te, cy, eq)

  defp query_clock(:now, client, t, _, _), do: send(client, {:time, t})
  defp query_clock(:events, client, _, eq, _), do: send(client, {:events, eq})
  defp query_clock(:state, client, _, _, s), do: send(client, {:state, s})
end
