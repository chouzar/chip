# Chip - A subject registry for Gleam

[![Package Version](https://img.shields.io/hexpm/v/chip)](https://hex.pm/packages/chip)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/chip/)

Chip is capable of registering a set of
[subjects](https://hexdocs.pm/gleam_erlang/gleam/erlang/process.html#Subject)
as part of a group.

## Example

Categorize subjects in groups, then send messages to them:

```gleam
import artifacts/game.{DrawCard, FireDice, PlayChip}
import chip
import gleam/list

pub type Group {
  GroupA
  GroupB
}

pub fn main() {
  let assert Ok(registry) = chip.start(chip.Unnamed)

  let assert Ok(session_a) = game.start(DrawCard)
  let assert Ok(session_b) = game.start(FireDice)
  let assert Ok(session_c) = game.start(PlayChip)

  chip.register(registry, GroupA, session_a)
  chip.register(registry, GroupB, session_b)
  chip.register(registry, GroupA, session_c)

  chip.members(registry, GroupA, 50)
  |> list.each(fn(session) { game.next(session) })
}
```

For more check the [docs and guildelines](https://hexdocs.pm/chip/).

## Development

New additions to the API will be considered with care. Features are
[documented as Issues](https://github.com/chouzar/chip/issues?q=is%3Aopen+is%3Aissue+label%3Aenhancement)
on the project's repo, if you have questions or like to see a new feature please open an issue.

Run tests:

```sh
gleam test
```

Run benchmarks:

```sh
gleam run --module benchmark
```

### Previous Art

This registry takes and combines some ideas from:

* Elixir’s [registry](https://hexdocs.pm/elixir/Kernel.html) module.
* Erlang's [pg](https://www.erlang.org/doc/apps/kernel/pg.html) module.
* The [syn](https://github.com/ostinelli/syn) global registry library.

### Other Gleam registry libraries

Other registry libraries will provide different semantics and functionality:

* [Singularity](https://hexdocs.pm/singularity/) is designed to register a fixed number of actors, where each one may have a different message type.

## Installation

```sh
gleam add chip
```
