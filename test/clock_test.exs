defmodule ClockTest do
  use ExUnit.Case
  doctest Events

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
    me = self()
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
    {:ok, %{events: events, time: t}} = Clock.step(clk)
    assert events == 1
    assert t == 2
    assert Utils.flush() == [2]
    assert Clock.update(clk, 5, :time, 5) == {:ok, 5}
    assert Clock.update(clk, 4, :fun, fn _ -> send(me, 10) end) == {:ok, 4}
    assert Clock.update(clk, 4, :cycle, 1) == {:ok, 4}
    {:ok, %{events: events, time: t}} = Clock.step(clk)
    assert events == 1
    assert t == 4
    assert Utils.flush() == [10]
    {:ok, %{events: events, time: t}} = Clock.step(clk)
    assert events == 2
    assert t == 5
    assert Utils.flush() == [10, 5]
    {:ok, %{events: events, time: t}} = Clock.step(clk)
    assert events == 1
    assert t == 6
    assert Utils.flush() == [10]
    assert Clock.reset(clk) == :ok

    {:state, %{client: client, evcount: evcount, state: state, tend: tend}} =
      Clock.query(clk, :state)

    assert client == self()
    assert evcount == 0
    assert state == :idle
    assert tend == 0
  end

  test "running clock" do
    clk = setup()
    me = self()
    Clock.update(clk, 5, :time, 5)
    Clock.update(clk, 4, :fun, fn _ -> send(me, 10) end)
    Clock.update(clk, 4, :cycle, 1)
    {:done, %{events: events, time: t}} = Clock.run(clk, 6)
    assert events == 7
    assert t == 6
    assert Utils.flush() == [1, 1, 2, 10, 10, 5, 10]
    {:done, %{events: events, time: t}} = Clock.run(clk, 4)
    assert events == 4
    assert t == 10
    assert Utils.flush() == [10, 10, 10, 10]
  end
end
