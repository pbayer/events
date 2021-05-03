defmodule Events.PQ do
  @moduledoc """
  `Events.PQ` describes event handling with a priority queue.

  An event is a `%Events.PQ` map containing

  - an execution time and
  - a function to call at that time.

  Events are hold in a priority search queue. An event's priority
  is determined by its time. Events with lower time are executed
  first.
  """
  defstruct t: 0.0, f: nil
  @type evt :: %Events.PQ{t: float, f: fun}
  @resolution 1000

  @doc "Create a new event queue (priority search queue)."
  @spec new() :: :psq.psq
  def new(), do: :psq.new()

  @doc "Add a new event `ev` to an event queue `psq`."
  @spec add(evt, :psq.psq) :: :psq.psq
  def add(ev, psq) do
    kp = trunc(ev.t*@resolution)
    {:ok, psq2} = :psq.alter(fn mv -> update(mv, kp, ev) end, kp, psq)
    psq2
  end

  defp update(:nothing, prio, ev) do
    {:ok, {:just, {prio, [ev]}}}
  end
  defp update({:just, {_, evts}}, prio, ev) do
    {:ok, {:just, {prio, evts ++ [ev]}}}
  end

  @doc """
  Execute the next event and remove it from the `psq` queue.
  Return a tuple of the event's time and the updated `psq`.
  """
  @spec next(:psq.psq) :: {number, :psq.psq}
  def next(psq) do
    case :psq.find_min(psq) do
      {:just, {_, _, evts}} -> exec_1st_event(evts, psq)
      :nothing              -> {nil, psq}
    end
  end

  defp exec_1st_event( [ev], psq) do
    psq = :psq.delete_min(psq)
    exec_1st_event(ev, psq)
  end
  defp exec_1st_event( [ev, _], psq) do
    {:ok, psq} = :psq.alter_min(&delete_1st/1, psq)
    exec_1st_event(ev, psq)
  end
  defp exec_1st_event( ev, psq) do
    ev.f.()
    {ev.t, psq}
  end

  defp delete_1st({:just, {k, p, [_ | t]}}) do
    {:ok, {:just, {k, p, t}}}
  end

end
