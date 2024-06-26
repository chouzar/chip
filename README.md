# chip

[![Package Version](https://img.shields.io/hexpm/v/chip)](https://hex.pm/packages/chip)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/chip/)


A local process registry that plays along with Gleam's [Subject](https://hexdocs.pm/gleam_erlang/gleam/erlang/process.html#Subject) type. 

It can hold to a set of subjects to later reference individually or dispatch a callback as a group. Will also automatically delist dead processes.

### Example

Lets assemble the pieces to build a simple counter actor:

```gleam
import gleam/erlang/process
import gleam/otp/actor

pub opaque type Message {
  Inc
  Current(client: process.Subject(Int))
}

pub fn increment(counter) {
  actor.send(counter, Inc)
}

pub fn current(counter) {
  actor.call(counter, Current(_), 10)
}

fn loop(message: Message, count: Int) {
  case message {
    Inc -> {
      actor.Continue(count + 1, option.None)
    }

    Current(client) -> {
      process.send(client, count)
      actor.Continue(count, option.None)
    }
  }
}
```

We start our registry and create new instances of a counter:

```gleam
import gleam/otp/actor
import chip/group

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
let assert 0 = counter.current(counter)
```

Or broadcast a message to all members:

```gleam
chip.dispatch(registry, fn(counter) {
  actor.increment(counter)
}) 

let assert Ok(counter) = chip.find(registry, 2)
let assert 1 = counter.current(counter)
```

## The road towards V1

Feature-wise this is near beign complete. Still planning to integrate: 

- [x] Adjust the API to be more in-line with other Registry libraries like elixir's Registry, erlang's pg or Syn. 
- [x] Document modules.
- [x] Basic test case scenarios.
- [X] Should play well with gleam style of supervisors. 
- [ ] Document guides and use-cases. 
- [ ] Build a benchmark that measures performance and memory consuption. 
- [ ] Implement an ETS backend. 
- [ ] Benchmark in-process backend vs ETS backend.

## Previous Art

This registry takes and combines some ideas from Elixir’s [Registry](https://hexdocs.pm/elixir/Kernel.html), Erlang’s [pg](https://www.erlang.org/doc/apps/kernel/pg.html) and [Syn](https://github.com/ostinelli/syn).

## Alternatives

[Singularity](https://hexdocs.pm/singularity/) is a gleam library that offers registry capabilities but focusing more on singleton actors, therefore it is better suited for keeping track of actors that need to be passed around as configuration through your app. 

## Installation

```sh
gleam add chip
```
