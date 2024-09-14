# Chip as part of a Supervision tree

A supervision tree is a strategy used in the wider erlang ecosystem to keep long-running processeess alive. When a process in the tree terminates the supervisor will attempt to restart the process and any subsequent processess in the tree, giving our whole system self-healing capabilities.

To make chip and other subjects part of a supervision tree we first need to define their respective child specifications, these specifications define their behaviour and state when starting or re-starting.

```gleam
import artifacts/game
import chip
import gleam/erlang/process
import gleam/otp/supervisor

type Registry =
  chip.Registry(game.Message, Int, Nil)

pub type Context {
  Context(caller: process.Subject(Registry), registry: Registry, id: Int)
}

pub fn registry() {
  // The registry childspec first starts the registry.
  supervisor.worker(fn(_caller: process.Subject(Registry)) { chip.start() })
  // After starting we transform the parameter from caller into a context for 
  // the sessions we want to register. 
  |> supervisor.returning(fn(caller, registry) { Context(caller, registry, 1) })
}

pub fn game() {
  supervisor.worker(fn(context: Context) {
    game.start_with(context.registry, context.id, game.DrawCard)
  })
  |> supervisor.returning(fn(context: Context, _game_session) {
    Context(..context, id: context.id + 1)
  })
}

pub fn ready() {
  // This childspec is a noop addition to the supervisor, on return it
  // will send back the registry reference.
  supervisor.worker(fn(_context: Context) { Ok(process.new_subject()) })
  |> supervisor.returning(fn(context: Context, _self) {
    process.send(context.caller, context.registry)
    Nil
  })
}
```

Then integrating our specs to a supervisor is simple enough: 

```gleam 
import artifacts/spec
import chip
import gleam/erlang/process
import gleam/list
import gleam/otp/supervisor

pub fn main() {
  let self = process.new_subject()

  let assert Ok(_supervisor) =
    supervisor.start_spec(
      supervisor.Spec(
        argument: self,
        max_frequency: 5,
        frequency_period: 1,
        init: fn(children) {
          children
          // First spawn the registry
          |> supervisor.add(spec.registry())
          // Then spawn 1 to 50 game sessions
          |> list.fold(
            list.range(1, 50),
            _,
            fn(children, _id) { supervisor.add(children, spec.game()) },
          )
          // Finally notify the main process we're ready
          |> supervisor.add(spec.ready())
        },
      ),
    )

  let assert Ok(registry) = process.receive(self, 500)
  let assert Ok(_session) = chip.find(registry, 33)
}
```

With the implementation above, we have asured that we will have our 1 to 50 game sessions always available for retireval.  
