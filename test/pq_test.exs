defmodule PQTest do
  use ExUnit.Case
  doctest Events

  alias Events.PQ

  def testset() do
    eq = PQ.new()
    eq = PQ.add(fn pid -> send(pid, 1) end, 1.0, nil, eq)
    eq = PQ.add(fn pid -> send(pid, 2) end, 1.0, nil, eq)
    PQ.add(fn pid -> send(pid, 3) end, 2.0, nil, eq)
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
    assert Map.keys(eq.evts) == [1, 2, 3]
    assert :psq.psq_size(eq.psq) == 2
    assert Enum.map([1, 2, 3], fn x -> eq.evts[x].t end) == [1.0, 1.0, 2.0]
  end

  test "Update events" do
    eq = testset()
    eq = PQ.update(4, :cycle, 1.0, eq)
    assert eq == testset()
    %{evts: evts} = PQ.update(2, :cycle, 1.0, eq)
    assert evts[2].c == 1.0
  end

  test "Execute next event" do
    me = self()
    eq = testset()
    {t, fs, eq} = PQ.next(eq)
    Enum.each(fs, fn f -> f.(me) end)
    assert t == 1.0
    assert length(fs) == 2
    assert length(Map.keys(eq.evts)) == 1
    assert Utils.flush() == [1, 2]
    {t, fs, eq} = PQ.next(eq)
    Enum.each(fs, fn f -> f.(me) end)
    assert t == 2.0
    assert length(fs) == 1
    assert eq.evts == %{}
    assert Utils.flush() == [3]
  end

  test "Execute with repeated event" do
    me = self()
    eq = testset()
    eq = PQ.update(2, :cycle, 1.0, eq)
    {t, fs, eq} = PQ.next(eq)
    Enum.each(fs, fn f -> f.(me) end)
    assert t == 1.0
    assert length(fs) == 2
    assert length(Map.keys(eq.evts)) == 2
    assert Utils.flush() == [1, 2]
    {t, fs, eq} = PQ.next(eq)
    Enum.each(fs, fn f -> f.(me) end)
    assert t == 2.0
    assert length(fs) == 2
    assert length(Map.keys(eq.evts)) == 1
    assert Utils.flush() == [3, 2]
    {t, fs, eq} = PQ.next(eq)
    Enum.each(fs, fn f -> f.(me) end)
    assert t == 3.0
    assert length(fs) == 1
    assert length(Map.keys(eq.evts)) == 1
    assert Utils.flush() == [2]
    # delete repeated event
    eq = PQ.delete(2, eq)
    {t, fs, eq} = PQ.next(eq)
    Enum.each(fs, fn f -> f.(me) end)
    assert eq.evts == %{}
    assert t == 4.0
    assert length(fs) == 0
    assert Utils.flush() == []
  end
end
