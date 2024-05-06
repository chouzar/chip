# chip

[![Package Version](https://img.shields.io/hexpm/v/chip)](https://hex.pm/packages/chip)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/chip/)


Chip is a gleam process registry that plays along the [Gleam Erlang](https://hexdocs.pm/gleam_erlang/) `Subject` type. 

It lets tag subjects under a name or group to later reference them. Will also automatically delist dead processes.

### Example

Lets assemble the pieces to build a simple counter actor:

```gleam
pub type Message {
  Inc
  Current(client: process.Subject(Int))
  Stop
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

    Stop -> {
      actor.Stop(process.Normal)
    }
  }
}
```

We start our registry and create new instances of a counter:

```gleam
import gleam/erlang/process
import chip

pub fn main() {
  let assert Ok(registry) = chip.start()

  let assert Ok(counter_1) = actor.start(1, loop)
  let assert Ok(counter_2) = actor.start(2, loop)
  let assert Ok(counter_3) = actor.start(3, loop)

  chip.group(registry, counter_1, "counters")
  chip.group(registry, counter_2, "counters")
  chip.group(registry, counter_3, "counters")
}
```

Later we can lookup for all subjects under the group and send messages: 

```gleam
chip.broadcast(registry, "counters", fn(counter) {
  actor.send(counter, Inc)
}) 

```

Or retrieve the current state of our subjects: 

```gleam
let assert [2, 3, 4] =  
  chip.members(registry, "counters")
  |> list.map(process.call(_, Current(_), 10))
  // Subject maybe be retrieved out of order so we do it explicitly
  |> list.sort(int.compare)
```

Feature-wise this is near beign complete. Still planning to integrate: 

- [ ] Modify the API to be more in-line with current elixir registry library. 
- [ ] Generally improve performance and memory consumption by running benchmarks. 
- [ ] Document guides and use-cases, make test cases more readable. 
- [X] Should play well with gleam style of supervisors. 

## Installation

```sh
gleam add chip
```
