import gleeunit
import gleam/erlang/process
import gleam/otp/actor
import chip

pub fn main() {
  gleeunit.main()
}

type Name {
  Actor1
  Actor2
  Actor3
}

pub fn start_test() {
  let assert Ok(_subject) = chip.start()
}

pub fn register_test() {
  // Initialize the Registry and register the actor under a name
  let assert Ok(registry) = chip.start()
  let assert Nil = chip.register(registry, Actor1, process.new_subject())
}

pub fn unregister_test() {
  // Initialize the Registry and register the actor under a name
  let assert Ok(registry) = chip.start()
  let assert Nil = chip.unregister(registry, Actor1)
}

pub fn find_test() {
  // Initialize actor and registry
  let assert Ok(actor) = actor_mock()
  let assert Ok(registry) = chip.start()

  // Register the process and fetch it
  chip.register(registry, Actor1, actor)
  chip.register(registry, Actor2, actor)

  let assert Ok(_) = chip.find(registry, Actor1)
  let assert Ok(_) = chip.find(registry, Actor2)
  let assert Error(_) = chip.find(registry, Actor3)

  // Unregister a process and try to fetch
  chip.unregister(registry, Actor1)
  let assert Error(chip.NotFound) = chip.find(registry, Actor1)
  let assert Ok(_) = chip.find(registry, Actor2)
  let assert Error(chip.NotFound) = chip.find(registry, Actor3)
}

pub opaque type MockMessage(message) {
  Stop(client: process.Subject(message))
}

fn actor_mock() {
  let handle_message = fn(message, _state) {
    case message {
      Stop(client) -> {
        process.send(client, Ok(Nil))
        actor.Stop(process.Normal)
      }
    }
  }

  actor.start(Nil, handle_message)
}
