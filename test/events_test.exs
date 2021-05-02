defmodule EventsTest do
  use ExUnit.Case
  doctest Events

  test "greets the world" do
    assert Events.hello() == :world
  end
end
