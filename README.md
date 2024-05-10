# chip

[![Package Version](https://img.shields.io/hexpm/v/chip)](https://hex.pm/packages/chip)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/chip/)


A local process registry that plays along Gleam's [Subject](https://hexdocs.pm/gleam_erlang/gleam/erlang/process.html#Subject) type.  

It lets tag subjects under a name or group to later reference them. Will also automatically delist dead processes.

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

  let assert Ok(counter_1) = actor.start(1, loop)
  let assert Ok(counter_2) = actor.start(2, loop)
  let assert Ok(counter_3) = actor.start(3, loop)

  group.register(registry, counter_1, "counters")
  group.register(registry, counter_2, "counters")
  group.register(registry, counter_3, "counters")
  
  process.sleep_forever()
}
```

Later, we may retrieve members for a group: 

```gleam
let assert [a, b, c] = group.members(registry, "counters")
let assert 6 = counter.current(a) + counter.current(b) + counter.current(c)
```

Or broadcast a message to each Subject:

```gleam
group.dispatch(registry, "counters", fn(counter) {
  actor.increment(counter)
}) 

let assert [a, b, c] = group.members(registry, "counters")
let assert 9 = counter.current(a) + counter.current(b) + counter.current(c)
```

Feature-wise this is near beign complete. Still planning to integrate: 

- [ ] Modify the API to be more in-line with other Registry libraries like elixir's Registry, erlang's pg or Syn. 
- [ ] Generally improve performance and memory consumption by running benchmarks. 
- [ ] Document guides and use-cases, make test cases more readable. 
- [X] Should play well with gleam style of supervisors. 

## Installation

```sh
gleam add chip
```
