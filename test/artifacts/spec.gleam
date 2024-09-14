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
