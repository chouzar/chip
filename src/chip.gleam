import gleam/io
import gleam/map
import gleam/erlang/process.{Subject}
import gleam/otp/actor

pub fn main() {
  io.println("Hello from chip!")
}

pub opaque type Message(name, message) {
  Register(name: name, subject: Subject(message))
}

pub fn start() {
  actor.start(map.new(), handle_message)
}

pub fn register(registry, name: name, subject: Subject(message)) -> Nil {
  process.send(registry, Register(name, subject))
}

pub fn unregister(registry, name: name) -> Nil {
  todo
}

pub fn find(registry, name: name) {
  todo
}

fn handle_message(message, state) {
  case message {
    Register(name, subject) -> {
      // TODO: temporarily stored internally here.
      // Eventually dispatch to a store (GenServer, ets, DB)
      let state = map.insert(state, name, subject)

      actor.continue(state)
    }
  }
}
