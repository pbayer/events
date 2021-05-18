# Events

Discrete event simulation (DES) framework in Elixir.

[![Elixir CI](https://github.com/pbayer/events/actions/workflows/ci.yml/badge.svg)](https://github.com/pbayer/events/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/pbayer/events/badge.svg?branch=master&kill_cache=1)](https://coveralls.io/github/pbayer/events?branch=master)

## Outline

Elixir is an [actor](https://en.wikipedia.org/wiki/Actor_model) language based on the [BEAM](https://en.wikipedia.org/wiki/BEAM_(Erlang_virtual_machine)) and thereby should enable `Events` to

- handle thousands of concurrent entities in a simulation,
- model them as actors and
- integrate the event-, activity- and process-based approaches to DES in one simple actor-framework.

## Goal

The goal of `Events` is to figure out how this can be done. The steps roughly are to

- [x] implement the basic clock and event handling functionality,
- [ ] write examples of event-, activity- and process-based simulations,
- [ ] explore further possibilities of Erlang/Elixir for DES,
- [ ] combine them into one convenient framework.

## Development

All this is in an early stage and only possible in principle. The constraint is my time and knowledge. It is a fascinating playground to find out more about it. Other people are welcome to comment and to join.

------------

## Installation

[Registration in Hex](https://hex.pm/docs/publish) will be done after the first steps (above) have been taken. Then the package can be installed by adding `events` to your list of dependencies in `mix.exs`:

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

