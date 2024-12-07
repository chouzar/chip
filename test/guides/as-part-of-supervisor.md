# Chip as part of a Supervision tree

In the wider erlang ecosystem a supervision tree defines a strategy to startup and monitor 
erlang processes, in case one of the supervised process shutdowns or fails, this same 
strategy will be restarted, giving the system self-healing capabilities.

To make chip and other subjects part of a supervision tree we need to define their child
specifications, these specifications define their behaviour and state when starting or
re-starting.

Lets assume we need to have multiple "sessions" indexed on our system:

```gleam
import chip
import gleam/erlang/process
import gleam/otp/supervisor

pub fn main() {
  let self = process.new_subject()
  let assert Ok(_supervisor) = supervisor(self)

  // Once initialized, the supervisor function will send back a message
  // with the child registry. From then we can use the registry to
  // find subjects.
  let assert Ok(registry) = process.receive(self, 500)
  let assert [_, _] = chip.members(registry, GroupA, 50)
  let assert [_, _] = chip.members(registry, GroupB, 50)
  let assert [_] = chip.members(registry, GroupC, 50)
}

// ------ Supervision Tree ------ //

// A context type will help carry around state between children in the supervisor.
type Context {
  Context(caller: process.Subject(Registry), registry: Registry, group: Group)
}

// The tree is defined by calling a hierarchy of specifications
fn supervisor(main: process.Subject(Registry)) {
  supervisor.start_spec(
    supervisor.Spec(
      argument: main,
      max_frequency: 5,
      frequency_period: 1,
      init: fn(children) {
        children
        // First spawn the registry.
        |> supervisor.add(registry_spec())
        // Then spawn all sessions.
        |> supervisor.add(session_spec())
        |> supervisor.add(session_spec())
        |> supervisor.add(session_spec())
        |> supervisor.add(session_spec())
        |> supervisor.add(session_spec())
        // Finally notify the main process we're ready.
        |> supervisor.add(ready())
      },
    ),
  )
}

// ------ Registry ------ //

type Registry =
  chip.Registry(Message, Group)

fn registry_spec() {
  // The registry childspec first starts the registry.
  supervisor.worker(fn(_caller: process.Subject(Registry)) {
    chip.start(chip.Named("sessions"))
  })
  // After starting we transform the parameter from caller into a context for
  // the sessions we want to register.
  |> supervisor.returning(fn(caller, registry) {
    Context(caller, registry, GroupA)
  })
}

// ------ Session ------- //

fn session_spec() {
  supervisor.worker(fn(context: Context) {
    start_session(context.registry, context.group)
  })
  |> supervisor.returning(fn(context: Context, _game_session) {
    // Increments the id for the next session.
    Context(..context, group: next_group(context.group))
  })
}

fn start_session(
  with registry: Registry,
  group group: Group,
) -> supervisor.StartResult(Message) {
  // Mock function to startup a new session.
  let session = process.new_subject()
  chip.register(registry, group, session)
  Ok(session)
}

// ------ Helpers ------ //

type Message =
  Nil

type Group {
  GroupA
  GroupB
  GroupC
}

fn next_group(group) {
  case group {
    GroupA -> GroupB
    GroupB -> GroupC
    GroupC -> GroupA
  }
}

fn ready() {
  // This childspec is a noop addition to the supervisor, on return it
  // will send back the registry reference.
  supervisor.worker(fn(_context: Context) { Ok(process.new_subject()) })
  |> supervisor.returning(fn(context: Context, _self) {
    process.send(context.caller, context.registry)
    Nil
  })
}
```
