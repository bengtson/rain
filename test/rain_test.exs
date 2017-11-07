defmodule RainTest do
  use ExUnit.Case
  doctest Rain

  test "greets the world" do
    assert Rain.hello() == :world
  end
end
