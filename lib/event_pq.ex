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

  alias __MODULE__, as: PQ

  @resolution 1000

  @doc "Create a new event queue."
  @spec new() :: %{no: non_neg_integer, evts: map, psq: :psq.psq}
  def new(), do: %{no: 0, evts: %{}, psq: :psq.new()}

  @doc """
  Insert a new event into an event queue and return it.

  - `f: fun`: function to execute,
  - `t: number`: event time,
  - `c: number`: cycle time for a repeating event, `nil` otherwise,
  - `eq: map`: event queue.
  """
  def add(f, t, c, eq) do
    n = eq.no+1
    ev = %PQ{t: t, f: f, c: c}
    %{eq | no: n, evts: Map.put(eq.evts, n, ev), psq: add_psq(n, t, eq.psq)}
  end

  @doc """
  Update event number `no`.
  """
  def update(no, :cycle, cy, eq), do: update_eq(no, :c, cy, eq)

  defp update_eq(no, key, value, eq) do
    %{no: _, evts: evts, psq: _} = eq
    case Map.get(evts, no) do
      nil -> eq
      ev ->
        ev = Map.update!(ev, key, fn _ -> value end)
        %{eq | evts: Map.update!(evts, no, fn _ -> ev end)}
    end
  end

  defp add_psq(n, t, psq) do
    kp = trunc(t*@resolution)
    {:ok, psq2} = :psq.alter(fn mv -> update_psq(mv, kp, n, t) end, kp, psq)
    psq2
  end

  defp update_psq(:nothing, prio, n, t) do
    {:ok, {:just, {prio, %{t: t, ens: [n]}}}}
  end
  defp update_psq({:just, {_, ev}}, prio, n, _) do
    {:ok, {:just, {prio, %{ev | ens: ev.ens ++ [n]}}}}
  end

  @doc """
  Execute the next event with argument `arg` and remove it from
  the `psq` queue. Return a tuple of
  - the event's time,
  - the number of executed functions and
  - the updated `psq`.
  """
  @spec next(pid, :psq.psq) :: {number, integer, :psq.psq}
  def next(arg, psq) do
    case :psq.find_min(psq) do
      {:just, {_, _, ev}} ->
        Enum.each(ev.ens, fn x -> x.(arg) end)
        psq = :psq.delete_min(psq)
        {ev.t, length(ev.ens), psq}
      :nothing ->
        {nil, 0, psq}
    end
  end

end
