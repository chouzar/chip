# Chip - A subject registry for Gleam

[![Package Version](https://img.shields.io/hexpm/v/chip)](https://hex.pm/packages/chip)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/chip/)

Chip is a performant local registry that can hold to a set of [subjects](https://hexdocs.pm/gleam_erlang/gleam/erlang/process.html#Subject) individually or as part of a group. 

## Example

One of the most useful use cases for chip is broadcasting messages to registered subjects:

```gleam
import artifacts/game.{DrawCard, FireDice, PlayChip}
import chip

pub fn main() {
  let assert Ok(registry) = chip.start()

  let assert Ok(session_a) = game.start(DrawCard)
  let assert Ok(session_b) = game.start(FireDice)
  let assert Ok(session_c) = game.start(PlayChip)

  chip.register(registry, chip.new(session_a))
  chip.register(registry, chip.new(session_b))
  chip.register(registry, chip.new(session_c))

  chip.dispatch(registry, fn(session) {
    game.next(session)
  })
}
```

## Features

Chip was designed with a very minimal but practical feature set:

* Subjects may be individually retrieved via tags.
* It is also possible to dispatch actions to groups of Subjects.
* Chip will automatically delist dead processes.

For more possible use-cases check the documented guidelines.

## Development 

From now on updates will focus on reliability and performance, but new additions to the API will be considered with care. Features are [documented as Issues](https://github.com/chouzar/chip/issues?q=is%3Aopen+is%3Aissue+label%3Aenhancement) on the project's repo, if you have questions or like to se a new feature please open an issue.

### Previous Art 

This registry takes and combines some ideas from:

* Elixir’s [registry](https://hexdocs.pm/elixir/Kernel.html) module.
* Erlang's [pg](https://www.erlang.org/doc/apps/kernel/pg.html) module.
* The [syn](https://github.com/ostinelli/syn) global registry library.

### Other Gleam registry libraries

Other registry libraries will provide different semantics and functionality:

* [Singularity](https://hexdocs.pm/singularity/) is designed to register a fixed number of actors, each of which may have a different message type.

## Installation

```sh
gleam add chip
```
