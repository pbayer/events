defmodule PQTest do
  use ExUnit.Case
  doctest Events

  alias Events.PQ

  def testset() do
    me = self()
    eq = PQ.new()
    eq = PQ.add(fn _ -> send me, 1 end, 1.0, nil, eq)
    eq = PQ.add(fn _ -> send me, 2 end, 1.0, nil, eq)
    PQ.add(fn _ -> send me, 3 end, 2.0, nil, eq)
  end

  test "Event queue creation" do
    %{no: no, evts: evts, psq: psq} = PQ.new()
    assert no == 0
    assert evts == %{}
    assert psq == nil
  end

  test "Add events" do
    eq = testset()
    assert eq.no == 3
    assert Map.keys(eq.evts) == [1,2,3]
    assert :psq.psq_size(eq.psq) == 2
    assert Enum.map([1,2,3], fn x -> eq.evts[x].t end) == [1.0, 1.0, 2.0]
  end
end
