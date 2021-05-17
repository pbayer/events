# Events

Discrete event simulation (DES) framework in Elixir.

[![Elixir CI](https://github.com/pbayer/events/actions/workflows/ci.yml/badge.svg)](https://github.com/pbayer/events/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/pbayer/events/badge.svg?branch=master&kill_cache=1)](https://coveralls.io/github/pbayer/events?branch=master)

With Elixir as an [actor](https://en.wikipedia.org/wiki/Actor_model) language based on the [BEAM](https://en.wikipedia.org/wiki/BEAM_(Erlang_virtual_machine)) `Events`

- can handle thousands of concurrent entities in a simulation,
- allows to model them as actors and
- integrates the event-, activity- and process-based approaches to DES in one simple actor-framework.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `events` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:events, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/events](https://hexdocs.pm/events).

