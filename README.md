# Chip - A subject registry library

[![Package Version](https://img.shields.io/hexpm/v/chip)](https://hex.pm/packages/chip)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/chip/)

Chip is a performant local registry that can hold to a set of [subjects](https://hexdocs.pm/gleam_erlang/gleam/erlang/process.html#Subject) to later retrieve or dispatch tasks to. 

### Example

Lets assemble a simple counter actor:

```gleam
import gleam/erlang/process
import gleam/otp/actor

pub type Message {
  Inc
  Current(client: process.Subject(Int))
}

fn loop(message: Message, count: Int) {
  case message {
    Inc -> {
      actor.continue(count + 1)
    }

    Current(client) -> {
      process.send(client, count)
      actor.continue(count)
    }
  }
}
```

We start our registry and create new instances of the counter:

```gleam
import chip
import gleam/otp/actor

pub fn main() {
  let assert Ok(registry) = chip.start()

  let assert Ok(counter_1) = actor.start(0, loop)
  let assert Ok(counter_2) = actor.start(0, loop)
  let assert Ok(counter_3) = actor.start(0, loop)

  chip.register(registry, chip.new(counter_1) |> chip.tag(1))
  chip.register(registry, chip.new(counter_2) |> chip.tag(2))
  chip.register(registry, chip.new(counter_3) |> chip.tag(3))
  
  process.sleep_forever()
}
```

Later, we may retrieve a member:
 
```gleam
let assert Ok(counter) = chip.find(registry, 2)
let assert 0 = actor.call(counter, Current(_), 10)
```

Or dispatch a task to all members or group:

```gleam
chip.dispatch(registry, fn(counter) {
  actor.send(counter, Inc)
}) 

let assert Ok(counter) = chip.find(registry, 2)
let assert 1 = actor.call(counter, Current(_), 10)
```

Chip will also automatically delist dead processes.

## The road towards V1

Feature-wise this is near beign complete. Still planning to integrate: 

- [X] Adjust the API to be more in-line with other Registry libraries like elixir's Registry, erlang's pg or Syn. 
- [X] Document modules.
- [X] Basic test case scenarios.
- [X] Should play well with gleam style of supervisors. 
- [X] Document guides and use-cases. 
- [X] Build a benchmark that measures performance. 
- [X] Build a benchmark that measures memory consuption. 
- [X] Implement an ETS backend. 
- [X] Benchmark in-process backend vs ETS backend.

Couple of adjustments and cleanup left for V1!

## Tentative features

[Documented as Issues](https://github.com/chouzar/chip) on this project's github repo. If you'd like to see a new feature please open an issue.

## Alternatives

### Previous Art 

This registry takes and combines some ideas from Elixir’s [Registry](https://hexdocs.pm/elixir/Kernel.html), Erlang’s [pg](https://www.erlang.org/doc/apps/kernel/pg.html) and [Syn](https://github.com/ostinelli/syn).

### Other Gleam registry libraries

[Singularity](https://hexdocs.pm/singularity/) is designed to register a fixed number of actors, each of which may have a different message type.

## Installation

```sh
gleam add chip
```
