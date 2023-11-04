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

pub fn delist_dead_process_test() {
  // Initialize actor and registry
  let assert Ok(actor) = actor_mock()
  let assert Ok(registry) = chip.start()

  // Register the process and try to fetch it
  chip.register(registry, Actor1, actor)
  chip.register(registry, Actor3, actor)

  let assert Ok(_) = chip.find(registry, Actor1)
  let assert Ok(_) = chip.find(registry, Actor3)

  // Kill process and try to fetch it
  let assert Ok(_) = process.call(actor, fn(self) { Stop(self) }, 10)

  let assert Error(_) = chip.find(registry, Actor1)
  let assert Error(_) = chip.find(registry, Actor3)
}

type CounterMessage(subject_message) {
  Inc
  Current(client: process.Subject(subject_message))
  Stop(client: process.Subject(subject_message))
}

type State(message) {
  Init(register: Subject(message), count: Int)
  Count(Int)
}

fn handle_count(message: CounterMessage(subject_message), state: State) {
  case state, message {
    Init(register, count), _message -> {
      chip.register(
    }
    
    Count(count), Inc -> {
      
    }
  }
  
  case message {
    Inc -> {
      actor.continue(count + 1)
    }

    Current(client) -> {
      process.send(client, count)
      actor.continue(count)
    }

    Stop(client) -> {
      process.send(client, Ok(Nil))
      actor.Stop(process.Normal)
    }
  }
}

pub fn counter_test() {
  let assert Ok(counter_a) = actor.start(0, handle_count)
  let assert Ok(counter_b) = actor.start(100, handle_count)

  let assert Ok(registry) = chip.start()
  chip.register(registry, "SmolCount", counter_a)
  chip.register(registry, "BigoCount", counter_b)
  // Meanwhile in another scope of your app...

  let assert Ok(counter_y) = chip.find(registry, "BigoCount")
  process.send(counter_y, Inc)
  process.send(counter_y, Inc)
  process.send(counter_y, Inc)

  let count = process.call(counter_y, fn(self) { Current(self) }, 10)

  let assert 103 = count
}
