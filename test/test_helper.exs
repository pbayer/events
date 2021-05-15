ExUnit.start()

defmodule Utils do
  def flush(acc \\ []) do
    receive do
      msg -> flush(acc ++ [msg])
    after
      0 -> acc
    end
  end
end
