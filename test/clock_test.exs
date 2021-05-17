defmodule ClockTest do
  use ExUnit.Case
  doctest Events

  alias Events.PQ
  alias Events.Clock

  def setup() do
    me = self()
    clk = Clock.clock()
    fun = fn c -> send(me, Clock.now(c)) end

    Enum.each([1, 1, 2, 4], fn t ->
      Clock.event(clk, {fun, :after, t, nil})
    end)

    Clock.event(clk, {fun, :at, 3, nil})
    clk
  end

  test "Idle clock" do
    clk = setup()
    assert Clock.now(clk) == 0
    {:events, eq} = Clock.query(clk, :events)
    assert length(Map.keys(eq.evts)) == 5

    {:state, %{client: client, evcount: evcount, state: state, tend: tend}} =
      Clock.query(clk, :state)

    assert client == self()
    assert evcount == 0
    assert state == :idle
    assert tend == 0
    {:ok, %{events: events, time: t}} = Clock.step(clk)
    assert events == 2
    assert t == 1
    assert Utils.flush() == [1, 1]
  end
end
