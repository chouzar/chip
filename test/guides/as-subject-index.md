# Chip as a session index

The main purpose of the process index is to be able to "track" individual subjects through an identifier in your application. The identifier may be an integer, string or even a union type if you only need few records.

```gleam
import chip
import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervisor

pub type Store(message) =
  chip.Registry(message, Int, Nil)

pub type Id =
  Int

pub fn start() -> Result(Store(message), actor.StartError) {
  chip.start()
}

pub fn childspec() {
  supervisor.worker(fn(_index) { start() })
}

pub fn index(store: Store(message), id: Id, subject: process.Subject(message)) {
  chip.new(subject)
  |> chip.tag(id)
  |> chip.register(store, _)
}

pub fn get(store: Store(message), id: Id) {
  chip.find(store, id)
}
```

Probably one of the most common uses cases for chip will involve looking up for subjects in your system. 

For example, in a web app we may add the registry as part of our app context. 

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

Of course, this ability to directly reference subjects is not very useful without a supervision tree, because if the subject dies we can no longer send messages to it. Check the [supervision guideline](as-part-of-supervisor.html) for more. 
