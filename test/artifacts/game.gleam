import chip
import gleam/erlang/process
import gleam/function
import gleam/otp/actor
import gleam/otp/supervisor

type SessionRegistry =
  chip.Registry(Message, Int, Nil)

type Game =
  process.Subject(Message)

pub type Action {
  DrawCard
  PlayChip
  FireDice
}

pub opaque type Message {
  Next
  Current(client: process.Subject(String))
  Stop
}

pub type Session {
  Session(Int)
}

pub fn start(action) {
  actor.start(action, loop)
}

pub fn start_with(registry: SessionRegistry, id: Int, action: Action) {
  let init = fn() { init(registry, id, action) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

pub fn childspec(registry: SessionRegistry, action) {
  supervisor.worker(fn(id) { start_with(registry, id, action) })
  |> supervisor.returning(fn(id, _self) { id + 1 })
}

pub fn next(game: Game) -> Nil {
  actor.send(game, Next)
}

pub fn current(game: Game) -> String {
  actor.call(game, Current(_), 100)
}

pub fn stop(game: Game) -> Nil {
  actor.send(game, Stop)
}

fn init(registry, id, action) {
  // Create a reference to self
  let self = process.new_subject()

  // Register the counter under an id on initialization
  chip.register(
    registry,
    chip.new(self)
      |> chip.tag(id),
  )

  // The registry may send messages through the self subject to this actor
  // adding self to this actor selector will allow us to handle those messages.
  actor.Ready(
    action,
    process.new_selector()
      |> process.selecting(self, function.identity),
  )
}

fn loop(message, action) {
  case message {
    Next -> next_state(action)
    Current(client) -> send_unicode(client, action)
    Stop -> actor.Stop(process.Normal)
  }
}

fn next_state(action) {
  actor.continue(case action {
    DrawCard -> PlayChip
    PlayChip -> FireDice
    FireDice -> DrawCard
  })
}

fn send_unicode(client, action) {
  process.send(client, case action {
    DrawCard -> "🂡"
    PlayChip -> "🪙"
    FireDice -> "🎲"
  })

  actor.continue(action)
}
