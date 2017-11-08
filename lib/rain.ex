defmodule Rain do
  @moduledoc """
  Documentation for Rain.
  """

  def start(_type, _args) do
  import Supervisor.Spec

  # Define workers and child supervisors to be supervised
  children = [
    # Start the endpoint when the application starts
    supervisor(Rain.Service, []),
    supervisor(Rain.Status, [])

    # Start your own worker by calling: Meteorologics.Worker.start_link(arg1, arg2, arg3)
    # worker(Meteorologics.Worker, [arg1, arg2, arg3]),
  ]

  # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
  # for other strategies and supported options
  opts = [strategy: :one_for_one, name: Rain.Supervisor]
  Supervisor.start_link(children, opts)
end


  @doc """
  Hello world.

  ## Examples

      iex> Rain.hello
      :world

  """
  def hello do
    :world
  end
end
