import chip
import gleam/erlang/process
import gleam/otp/supervisor

type Registry =
  chip.Registry(Message, Int)

// A context type will help carry round state at the supervisor.
type Context {
  Context(caller: process.Subject(Registry), registry: Registry, id: Int)
}

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
          // First spawn the registry.
          |> supervisor.add(registry_spec())
          // Then spawn all sessions.
          |> supervisor.add(session_spec())
          |> supervisor.add(session_spec())
          |> supervisor.add(session_spec())
          // Finally notify the main process we're ready.
          |> supervisor.add(ready())
        },
      ),
    )

  // The ready helper will send back a message with our registry.
  let assert Ok(registry) = process.receive(self, 500)
  let assert [_session_2] = chip.members(registry, 2, 50)
}

fn registry_spec() {
  // The registry childspec first starts the registry.
  supervisor.worker(fn(_caller: process.Subject(Registry)) {
    chip.start(chip.Named("sessions"))
  })
  // After starting we transform the parameter from caller into a context for
  // the sessions we want to register.
  |> supervisor.returning(fn(caller, registry) { Context(caller, registry, 1) })
}

// Mock helpers to emulate a session.
type Message =
  Nil

fn start_session(
  with registry: Registry,
  id id: Int,
) -> supervisor.StartResult(Message) {
  // Mock function to startup a new session.
  let session = process.new_subject()
  chip.register(registry, id, session)
  Ok(session)
}

fn session_spec() {
  supervisor.worker(fn(context: Context) {
    start_session(context.registry, context.id)
  })
  |> supervisor.returning(fn(context: Context, _game_session) {
    // Increments the id for the next session.
    Context(..context, id: context.id + 1)
  })
}

// Helper to return the registry's subject to the main flow.
fn ready() {
  // This childspec is a noop addition to the supervisor, on return it
  // will send back the registry reference.
  supervisor.worker(fn(_context: Context) { Ok(process.new_subject()) })
  |> supervisor.returning(fn(context: Context, _self) {
    process.send(context.caller, context.registry)
    Nil
  })
}
