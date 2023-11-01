import gleam/io
import gleam/erlang/process.{Subject}
import gleam/otp/actor

pub fn main() {
  io.println("Hello from chip!")
}

pub fn start() {
  actor.start(Nil, handle_message)
}

pub fn register(registry, name: name, subject: Subject(message)) -> Nil {
  todo
}

pub fn unregister(registry, name: name) -> Nil {
  todo
}

pub fn find(registry, name: name) {
  todo
}

fn handle_message(message, state) {
  actor.continue(state)
}
