defmodule Events.Clock do
  @moduledoc """
  `Events.Clock` defines a virtual clock for executing events on
  a virtual time line. An event is a function to execute at a
  virtual time `t`.

  A `clock_unit/3` is an Elixir process that
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

  # --------------------------------------
  # API for managing events
  # --------------------------------------

  @doc """
  Schedule a new event to a clock `clk` and return the event number.
  """
  @spec event(pid, event) :: {:ok, pos_integer} | {:error, :timeout}
  def event(clk, {_f, timing, _t, _c} = evt) when timing in [:at, :after] do
    send(clk, {self(), :event, :add, evt})

    receive do
      {:ok, _no} = msg -> msg
    after
      5000 ->
        IO.puts(:stderr, "No clock #{clk} response in 5 s")
        {:error, :timeout}
    end
  end

  @doc """
  Tell a clock `clk` to update event `no`

  - `:cycle, cy`: update its cycle to `cy`,
  - `:fun, f`: update its function to `f`,
  - `:time, t`: update its time to `t`.
  """
  @spec update(pid, pos_integer, :cycle, number) ::
          {:ok, pos_integer} | {:error, :timeout}
  def update(clk, no, :cycle, cy), do: _update(clk, {no, :cycle, cy})

  @spec update(pid, pos_integer, :fun, fun) ::
          {:ok, pos_integer} | {:error, :timeout}
  def update(clk, no, :fun, f), do: _update(clk, {no, :fun, f})

  @spec update(pid, pos_integer, :time, number) ::
          {:ok, pos_integer} | {:error, :timeout}
  def update(clk, no, :time, t), do: _update(clk, {no, :time, t})

  defp _update(clk, arg) do
    send(clk, {self(), :event, :update, arg})

    receive do
      {:ok, _no} = msg -> msg
    after
      5000 ->
        IO.puts(:stderr, "No clock #{clk} response in 5 s")
        {:error, :timeout}
    end
  end

  # --------------------------------------
  # API for controlling a clock
  # --------------------------------------
  @doc """
  Start a new `clock_unit/3` process with an empty event queue and a
  start time `t0` and return its `pid`.
  """
  @spec clock(number) :: pid
  def clock(t0 \\ 0) do
    client = self()

    spawn(Events.Clock, :clock_unit, [
      t0,
      PQ.new(),
      %{evcount: 0, state: :idle, tend: t0, client: client}
    ])
  end

  @doc "Tell an idle clock `clk` to take one step forward in time."
  @spec step(pid, pos_integer) :: {:ok, map} | {:error, :timeout}
  def step(clk, timeout \\ 5000) do
    send(clk, {self(), :clock, :step, nil})

    receive do
      {:ok, _} = msg -> msg
    after
      timeout ->
        IO.puts(:stderr, "No clock #{clk} response in #{timeout / 1000} s")
        {:error, :timeout}
    end
  end

  @doc "Run a clock `clk` synchronously for a time `t`."
  @spec run(pid, number, pos_integer) :: {:done, map} | {:error, :timeout}
  def run(clk, t, timeout \\ 10000) do
    _run(clk, t)

    receive do
      {:done, _} = msg -> msg
    after
      timeout ->
        IO.puts(:stderr, "No clock #{clk} response in #{timeout / 1000} s")
        {:error, :timeout}
    end
  end

  @doc "Run a clock `clk` for a time `t`."
  def _run(clk, t), do: send(clk, {self(), :clock, :run, t})

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
  @spec query(pid, atom, number) :: {atom, any}
  def query(clk, item, timeout \\ 5000) do
    _query(clk, item)

    receive do
      msg -> msg
    after
      timeout ->
        IO.puts(:stderr, "No clock #{clk} response in #{timeout / 1000} s")
        {:error, :timeout}
    end
  end

  @doc "Query a clock for an `item` to send it back to `self()`."
  def _query(clk, item), do: send(clk, {self(), :clock, :query, item})

  @doc "Reset a clock `clk`."
  def reset(clk, t0 \\ 0) do
    send(clk, {self(), :clock, :reset, t0})

    receive do
      {:ok} -> :ok
      msg -> msg
    end
  end

  # --------------------------------------
  # The clock machinery
  # --------------------------------------
  @doc """
  A `clock_unit` is a process controlling an event queue.
  It allows to

  - schedule events and to
  - execute them on a virtual timeline.

  The `clock_unit` executes events as tasks and thus
  remains always responsive e.g. to queries or insertion of new
  events. Its time line is virtual in the sense that it
  doesn't have a fixed time interval bound to physical time but
  it executes events in order and jumps from event to event
  thereby incrementing its time.

  `clock_unit` should not be called by a user but should instead
  be started with `clock/1`.
  """
  @spec clock_unit(number, PQ.event_queue(), map) :: tuple
  def clock_unit(t, eq, s) do
    receive do
      # manage events
      {caller, :event, command, arg} ->
        eq = manage_event(caller, command, arg, t, eq)
        clock_unit(t, eq, s)

      # control the clock_unit
      {caller, :clock, command, arg} ->
        ctrl_clock(caller, command, arg, {t, eq, s})

      # handle next event
      {:next, res} ->
        handle_next(t, eq, s, res)

      msg ->
        IO.puts("Clock #{self()} undefined message #{msg}")
        clock_unit(t, eq, s)
    end
  end

  # -------------------------------------
  # manage events
  # -------------------------------------
  defp manage_event(caller, :add, evt, t, eq) do
    eq = add_event(evt, t, eq)
    send(caller, {:ok, eq.no})
    eq
  end

  defp manage_event(caller, :update, {no, item, arg}, _, eq) do
    eq = PQ.update(no, item, arg, eq)
    send(caller, {:ok, no})
    eq
  end

  defp add_event({f, :at, te, cy}, _, eq), do: PQ.add(f, te, cy, eq)
  defp add_event({f, :after, te, cy}, t, eq), do: PQ.add(f, t + te, cy, eq)

  # -------------------------------------
  # control the clock_unit
  # -------------------------------------

  # query the clock_unit for an item
  defp ctrl_clock(caller, :query, item, {t, eq, s}) do
    query_clock(item, caller, {t, eq, s})
    clock_unit(t, eq, s)
  end

  # run the clock_unit for a time tr
  defp ctrl_clock(caller, :run, tr, {t, eq, %{state: :idle} = s}) do
    t0 = t
    {t, fs, eq} = PQ.next(eq)
    next_event(fs)

    clock_unit(t, eq, %{
      s
      | evcount: length(fs),
        state: :running,
        tend: t0 + tr,
        client: caller
    })
  end

  # step an idle clock_unit forward in time
  defp ctrl_clock(caller, :step, _, {_, eq, %{state: :idle} = s}) do
    {t, fs, eq} = PQ.next(eq)
    next_event(fs)

    clock_unit(t, eq, %{
      s
      | evcount: s.evcount + length(fs),
        client: caller
    })
  end

  # reset an idle clock_unit
  defp ctrl_clock(caller, :reset, t0, {_, _, %{state: :idle}}) do
    send(caller, {:ok})

    clock_unit(
      t0,
      PQ.new(),
      %{evcount: 0, state: :idle, tend: t0, client: caller}
    )
  end

  # stop a running clock_unit
  defp ctrl_clock(caller, :stop, _, {t, eq, %{state: :running} = s}) do
    clock_unit(t, eq, %{s | state: :stopped, client: caller})
  end

  # catch all
  defp ctrl_clock(caller, cmd, arg, {t, eq, s}) do
    IO.puts("Wrong :clock command #{cmd} from #{caller}")
    IO.puts("  arguments: #{arg},")
    IO.puts("  time: #{t}, state: #{s}")
    clock_unit(t, eq, s)
  end

  defp query_clock(:now, caller, {t, _, _}), do: send(caller, {:time, t})
  defp query_clock(:events, caller, {_, eq, _}), do: send(caller, {:events, eq})
  defp query_clock(:state, caller, {_, _, s}), do: send(caller, {:state, s})

  # -------------------------------------
  # execute events
  # -------------------------------------
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

  defp handle_next(t, eq, %{state: :stopped} = s, _) do
    send(s.client, {:stopped, %{events: s.evcount, time: t}})
    clock_unit(t, eq, %{s | state: :idle})
  end

  defp handle_next(t, eq, %{state: :idle} = s, res) do
    send(s.client, {:ok, %{events: length(res), time: t}})
    clock_unit(t, eq, s)
  end

  defp handle_next(t, eq, s, _) do
    if t >= s.tend || eq.psq == nil do
      t = max(s.tend, t)
      send(s.client, {:done, %{events: s.evcount, time: t}})
      clock_unit(t, eq, %{s | state: :idle})
    else
      {t, fs, eq} = PQ.next(eq)
      next_event(fs)
      evcount = s.evcount + length(fs)
      clock_unit(t, eq, %{s | evcount: evcount})
    end
  end
end
