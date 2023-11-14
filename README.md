# chip

[![Package Version](https://img.shields.io/hexpm/v/chip)](https://hex.pm/packages/chip)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/chip/)


Chip is a gleam process registry that plays along gleam erlang/OTP `Subject` type. 

It lets us group subjects of the same type so that we can later reference them all 
as a group, or sub-group if we decide to name them. Will also automatically delist 
dead processes.

### Example

Lets assemble the pieces to build a simple counter actor:

```gleam
pub type CounterMessage {
  Inc
  Current(client: process.Subject(Int))
  Stop(client: process.Subject(Int))
}

fn handle_count(message: CounterMessage, count: Int) {
  case message {
    Inc -> {
      actor.continue(count + 1)
    }

    Current(client) -> {
      process.send(client, count)
      actor.continue(count)
    }

    Stop(client) -> {
      process.send(client, count)
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

  chip.register(registry, fn() { 
    actor.start(1, handle_count)
  })
  
  chip.register(registry, fn() { 
    actor.start(2, handle_count)
  })
  
  chip.register(registry, fn() { 
    actor.start(3, handle_count)
  })
}
```

Then retrieve all registered subjects so we can send messages:
```gleam
chip.all(registry) 
|> list.each(process.send(_, Inc))

let assert [2, 3, 4] =  
  chip.all(registry)
  |> list.map(process.call(_, Current(_), 10))
  |> list.sort(int.compare)
```

It is also possible to register a subject under a named subgroup: 
```gleam
import gleam/erlang/process
import chip

type Group {
  GroupA 
  GroupB 
}

pub fn main() {
  let assert Ok(registry) = chip.start()

  chip.register_as(registry, GroupA, fn() { 
    actor.start(1, handle_count)
  })
  
  chip.register(registry, GroupB, fn() { 
    actor.start(2, handle_count)
  })
  
  chip.register(registry, GroupA, fn() { 
    actor.start(3, handle_count)
  })
}
```

Then lookup for specific names under the group:
```gleam
let assert [1, 3] = 
  chip.lookup(registry, GroupA) 
  |> list.map(process.call(_, Current(_), 10))
  |> list.sort(int.compare)
```

Feature-wise this is near beign complete. Still planning to integrate: 

* A `via` helper to initialize processes explicitly, currently `register` and `register_as`).
* A `register` helper to implicitly initialize subjects.
* Pending to document guides and use-cases.

## Installation

```sh
gleam add chip
```