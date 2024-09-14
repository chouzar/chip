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
