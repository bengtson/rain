# Rain

Rain provides a micro-service for Tack Så Mycket precipitation tracking.
A rain gauge located at the home sends a 'tip' timestamp to this service
for each 1/100th of an inch of rain.

This service records the tip in a file but also listens for any requests for
precipitation data. The service also sends a notification to the audio
notification system and provides status to the Tack Status system.

## ToDo Items

Following items are on the list of things to fix or features to add.

  - Add ability for the server to respond to a meteorologics request.
  - ExDoc complete.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `rain` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rain, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/rain](https://hexdocs.pm/rain).
