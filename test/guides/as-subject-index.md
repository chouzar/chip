# Chip as a session index

We may use chip to track individual subjects through an identifier. The
identifier may be an integer, string or even a union type if you only
need few records.

This pattern would be a way of re-defining chip as an indexed store:

```gleam
import chip
import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervisor

pub type Store(message) =
  chip.Registry(message, Int)

pub type Id =
  Int

pub fn start() -> Result(Store(message), actor.StartError) {
  chip.start(chip.Unnamed)
}

pub fn childspec() {
  supervisor.worker(fn(_index) { start() })
}

pub fn index(store: Store(message), id: Id, subject: process.Subject(message)) {
  chip.register(store, id, subject)
}

pub fn get(store: Store(message), id: Id) {
  case chip.members(store, id, 50) {
    [] -> Error(Nil)
    [subject] -> Ok(subject)
    [_, ..] -> panic as "Shouldn't insert more than 1 subject."
  }
}
```

It may be used to retrieve information from out of bound subjects. For example,
in a web app we may add the registry as part of our app context:

```gleam
import artifacts/game.{DrawCard}
import artifacts/store

pub fn main() {
  let assert Ok(sessions) = store.start()

  let assert Ok(session_1) = game.start(DrawCard)
  let assert Ok(session_2) = game.start(DrawCard)
  let assert Ok(session_3) = game.start(DrawCard)

  store.index(sessions, 1, session_1)
  store.index(sessions, 2, session_2)
  store.index(sessions, 3, session_3)

  router(sessions, "/resource/", 2)
}

fn router(sessions, url, id) {
  case url, id {
    "/resource/", id -> render_resource(sessions, id)
    _other, _id -> render_error()
  }
}

fn render_resource(sessions, id) {
  case store.get(sessions, id) {
    Ok(session) -> game.current(session)
    Error(Nil) -> render_error()
  }
}

fn render_error() {
  "Print Error"
}
```

Of course, if our sessions die we can no longer reference them through the index.
For process restart strategies check the [supervision guideline](as-part-of-supervisor.html).
