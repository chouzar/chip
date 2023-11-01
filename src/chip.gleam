import gleam/io
import gleam/erlang/process.{Subject}

pub fn main() {
  io.println("Hello from chip!")
}

pub fn start() {
  todo
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
