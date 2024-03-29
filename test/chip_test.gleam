import gleeunit
import gleam/function
import gleam/erlang/process
import gleam/otp/supervisor
import gleam/otp/actor
import chip

pub fn main() {
  gleeunit.main()
}

pub fn avoid_race_conditions_test() {
  let assert Ok(registry) = chip.start()

  // We can register unique names
  let assert Ok(_counter_1) = start_counter(0, registry, "counter-1")
  let assert Ok(_counter_2) = start_counter(0, registry, "counter-2")
  let assert Ok(counter_3) = start_counter(0, registry, "counter-3")

  // We can overwrite existing names 
  let Nil = chip.register(registry, counter_3, "counter-2")

  // To avoid a race condition we may do a find and register
  case chip.find(registry, "counter-4") {
    Ok(counter) -> {
      counter
    }

    Error(Nil) -> {
      let assert Ok(counter_4) = start_counter(10, registry, "counter-4")
      counter_4
    }
  }
}

pub fn how_grouping_works_test() {
  let assert Ok(registry) = chip.start()

  // We can register unique names
  let assert Ok(counter_1) = start_counter(0, registry, "counter-1")
  let assert Ok(counter_2) = start_counter(0, registry, "counter-2")
  let assert Ok(counter_3) = start_counter(0, registry, "counter-3")
  let assert Ok(counter_4) = start_counter(0, registry, "counter-4")
  let assert Ok(counter_5) = start_counter(0, registry, "counter-5")
  let assert Ok(counter_6) = start_counter(0, registry, "counter-6")

  // We can also group subjects
  chip.group(registry, counter_1, GroupA)
  chip.group(registry, counter_2, GroupB)
  chip.group(registry, counter_3, GroupB)
  chip.group(registry, counter_4, GroupC)
  chip.group(registry, counter_5, GroupC)
  chip.group(registry, counter_6, GroupC)

  // And retrieve members
  let assert [_] = chip.members(registry, GroupA)
  let assert [_, _] = chip.members(registry, GroupB)
  let assert [_, _, _] = chip.members(registry, GroupC)
  let assert [] = chip.members(registry, GroupD)
  let assert [] = chip.members(registry, GroupE)
}

pub fn chip_plus_supervisors_test() {
  let assert Ok(registry) = chip.start()

  let assert Ok(_supervisor) =
    supervisor.start(fn(children) {
      children
      |> supervisor.add(
        supervisor.worker(fn(_) { start_counter(10, registry, "my-counter") }),
      )
    })

  let counter = find_until(registry, "my-counter", 50)
  let _count = stop_counter(counter)
  let new_counter = find_until(registry, "my-counter", 50)

  let assert False = counter == new_counter
}

fn find_until(registry, name, milliseconds) {
  case milliseconds, chip.find(registry, name) {
    _milliseconds, Ok(subject) -> {
      subject
    }

    milliseconds, Error(Nil) if milliseconds > 0 -> {
      process.sleep(milliseconds)
      find_until(registry, name, milliseconds - 5)
    }

    _milliseconds, Error(Nil) -> {
      panic as "Process not found"
    }
  }
}

//*---------------- Test helpers to setup and tag a tests ----------------*//

// The different "channel" or "group" a subject may be part of 
type Groups {
  GroupA
  GroupB
  GroupC
  GroupD
  GroupE
}

/// This is an example Counter Actor used thorough the test suite.
pub opaque type Message {
  Inc
  Current(client: process.Subject(Int))
  Stop(client: process.Subject(Int))
}

fn start_counter(count: Int, registry, name: String) {
  actor.start_spec(actor.Spec(
    init: fn() { init(count, registry, name) },
    init_timeout: 10,
    loop: loop,
  ))
}

fn stop_counter(counter: process.Subject(Message)) -> Int {
  actor.call(counter, Stop(_), 10)
}

fn init(count, registry, name) {
  let self = process.new_subject()

  let selector =
    process.new_selector()
    |> process.selecting(self, function.identity)

  chip.register(registry, self, name)

  actor.Ready(count, selector)
}

fn loop(message: Message, count: Int) {
  case message {
    Inc -> {
      actor.continue(count + 1)
    }

    Current(client) -> {
      process.send(client, count)
      actor.continue(count)
    }

    Stop(client) -> {
      process.send(client, count)
      actor.Stop(process.Normal)
    }
  }
}
