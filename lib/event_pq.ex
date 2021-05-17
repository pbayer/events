defmodule Events.PQ do
  @moduledoc """
  `Events.PQ` describes event handling with a priority queue.

  An event is a map containing

  - `t :: number`: an execution time,
  - `f :: fun`: a function to call at that time,
  - `c :: number`: a cycle time for repeated events.

  An event gets registered in a map with a serial number key and
  can be changed or deleted with that key.

  Events are hold in a priority search queue. An event's priority
  is determined by its time `t`. Events with lower time are
  executed first.
  """
  defstruct t: 0, f: nil, c: nil
  @type ev :: %__MODULE__{t: number, f: fun, c: number}

  @typedoc """
  An `events`-map has event numbers as keys and an `ev`-struct value.
  """
  @type events :: %{pos_integer => ev}

  @typedoc """
  An `event_queue` is a map of

  - `:no`: number of last added event,
  - `:evts`: an events map with an entry for each active event,
  - `:psq`: a priority search queue where events get scheduled
    according to their time `t`.
  """
  @type event_queue :: %{
          no: non_neg_integer,
          evts: events,
          psq: :psq.psq()
        }

  alias __MODULE__, as: PQ

  @resolution 1000

  @doc """
  Create a new event queue.
  """
  @spec new :: event_queue
  def new, do: %{no: 0, evts: %{}, psq: :psq.new()}

  @doc """
  Insert a new event into an event queue and schedule it with
  - `f: fun`: function to execute,
  - `t: number`: event time,
  - `c: number`: cycle time for a repeating event, `nil` otherwise,
  - `eq: map`: event queue.

  Note: You can extract the generated event number as the
  `eq.no`-field of the returned event queue `eq`.
  """
  @spec add(fun, number, number, event_queue) :: event_queue
  def add(f, t, c, eq) do
    n = eq.no + 1
    ev = %PQ{t: t, f: f, c: c}
    %{eq | no: n, evts: Map.put(eq.evts, n, ev), psq: add_psq(n, t, eq.psq)}
  end

  @doc """
  Update event number `no` with

  - `:cycle`: update the event repeat cycle,
  - `:fun`: update the event function,
  - `:time`: update the event time
  """
  @spec update(pos_integer, :cycle, number, event_queue) :: event_queue
  def update(no, :cycle, cy, eq), do: update_eq(no, :c, cy, eq)

  @spec update(pos_integer, :fun, fun, event_queue) :: event_queue
  def update(no, :fun, f, eq), do: update_eq(no, :f, f, eq)

  @spec update(pos_integer, :time, number, event_queue) :: event_queue
  def update(no, :time, t, eq) do
    t_old = eq.evts[no].t
    kp = key(t_old)
    eq = update_eq(no, :t, t, eq)

    case :psq.lookup(kp, eq.psq) do
      {:just, {k, %{ens: ens}}} ->
        psq =
          if length(ens) <= 1 do
            :psq.delete(k, eq.psq)
          else
            ens = Enum.reject(ens, fn x -> x == no end)

            {:ok, psq} =
              :psq.alter(
                fn
                  mv -> update_psq(mv, kp, ens, t)
                end,
                kp,
                eq.psq
              )

            psq
          end

        %{eq | psq: add_psq(no, t, psq)}

      :nothing ->
        eq
    end
  end

  defp update_eq(no, key, value, eq) do
    %{no: _, evts: evts, psq: _} = eq

    case Map.get(evts, no) do
      nil ->
        eq

      ev ->
        ev = Map.update!(ev, key, fn _ -> value end)
        %{eq | evts: Map.update!(evts, no, fn _ -> ev end)}
    end
  end

  # calculate a key from a time
  defp key(t), do: trunc(t * @resolution)

  # add event number n at time t to a psq
  defp add_psq(n, t, psq) do
    kp = key(t)
    {:ok, psq2} = :psq.alter(fn mv -> update_psq(mv, kp, n, t) end, kp, psq)
    psq2
  end

  defp update_psq(:nothing, prio, n, t) do
    {:ok, {:just, {prio, %{t: t, ens: [n]}}}}
  end

  defp update_psq({:just, {_, ev}}, prio, ens, _) when is_list(ens) do
    {:ok, {:just, {prio, %{ev | ens: ens}}}}
  end

  defp update_psq({:just, {_, ev}}, prio, n, _) do
    {:ok, {:just, {prio, %{ev | ens: ev.ens ++ [n]}}}}
  end

  @doc "Delete event/s `n`/`ns` from the events list"
  @spec delete(integer, map) :: map
  def delete(n, eq) when is_integer(n) do
    %{eq | evts: Map.drop(eq.evts, [n])}
  end

  @spec delete(list, map) :: map
  def delete(ns, eq) when is_list(ns) do
    %{eq | evts: Map.drop(eq.evts, ns)}
  end

  @doc """
  Extract the events for the next time increment and either
  - remove them from the event list and queue or
  - schedule repeat events if an event's cycle `:c` is > 0.

  Return a tuple of
  - the event time,
  - a list of functions to execute,
  - the updated event queue.
  """
  @spec next(event_queue) :: {number, list, map}
  def next(%{no: no, evts: evts, psq: psq}) do
    case :psq.find_min(psq) do
      {:just, {_, _, ev}} ->
        # intersection
        evs = ev.ens -- ev.ens -- Map.keys(evts)
        # functions to execute
        flist = Enum.map(evs, fn n -> evts[n].f end)
        # cyclic events
        evc = Enum.filter(evs, fn n -> evts[n].c end)
        psq = reschedule_cyclic(evc, psq, evts, ev.t)
        # drop others
        evts = Map.drop(evts, evs -- evc)
        # delete
        psq = :psq.delete_min(psq)
        {ev.t, flist, %{no: no, evts: evts, psq: psq}}

      :nothing ->
        {-9999, [], %{no: no, evts: evts, psq: psq}}
    end
  end

  # reschedule cyclic events
  defp reschedule_cyclic(ns, psq, evts, t) do
    Enum.reduce(ns, psq, fn n, pq -> add_psq(n, t + evts[n].c, pq) end)
  end
end
