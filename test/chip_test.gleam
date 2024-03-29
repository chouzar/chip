import gleeunit
import gleam/int
import gleam/list
import gleam/erlang/process.{
  type Pid, type ProcessDown, type ProcessMonitor, type Selector, type Subject,
}
import gleam/otp/actor
import chip

pub fn main() {
  gleeunit.main()
}

pub fn gluncle_tests() {
  describe("avoid race conditions on same name?", setup, fn(context) {
    let Context(registry, c1, c2, c3, c4, ..) = context

    // We can register unique names 
    let Nil = chip.register(registry, c1, "one")
    let Nil = chip.register(registry, c2, "two")
    let Nil = chip.register(registry, c3, "three")

    // We can also overwrite existing names 
    let Nil = chip.register(registry, c1, "two")

    // To avoid a race condition we may do a find and register
    case chip.find(registry, "four") {
      Ok(counter) -> {
        counter
      }

      Error(Nil) -> {
        let Nil = chip.register(registry, c4, "four")
        c4
      }
    }
  })

  describe("this is how grouping works", setup, fn(context) {
    let Context(registry, c1, c2, c3, c4, c5, c6) = context
    chip.group(registry, c1, GroupA)
    chip.group(registry, c2, GroupB)
    chip.group(registry, c3, GroupB)
    chip.group(registry, c4, GroupC)
    chip.group(registry, c5, GroupC)
    chip.group(registry, c6, GroupC)

    let assert [_] = chip.members(registry, GroupA)
    let assert [_, _] = chip.members(registry, GroupB)
    let assert [_, _, _] = chip.members(registry, GroupC)
    let assert [] = chip.members(registry, GroupD)
    let assert [] = chip.members(registry, GroupE)
  })
}

/// ---------------- Test helpers to setup and tag a tests ---------------- ///
type Context {
  Context(
    registry: Subject(chip.Message(String, Groups, Message)),
    counter_1: Subject(Message),
    counter_2: Subject(Message),
    counter_3: Subject(Message),
    counter_4: Subject(Message),
    counter_5: Subject(Message),
    counter_6: Subject(Message),
  )
}

fn setup() -> Context {
  let assert Ok(registry) = chip.start()

  let assert Ok(c1) = start_counter(10)
  let assert Ok(c2) = start_counter(100)
  let assert Ok(c3) = start_counter(1000)
  let assert Ok(c4) = start_counter(10_000)
  let assert Ok(c5) = start_counter(100_000)
  let assert Ok(c6) = start_counter(1_000_000)

  Context(registry, c1, c2, c3, c4, c5, c6)
}

type Groups {
  GroupA
  GroupB
  GroupC
  GroupD
  GroupE
}

fn describe(
  _name: String,
  setup: fn() -> Context,
  test_case: fn(Context) -> x,
) -> x {
  test_case(setup())
}

/// This is an example Counter Actor used thorough the test suite.
pub opaque type Message {
  Inc
  Current(client: process.Subject(Int))
  Stop(client: process.Subject(Int))
}

fn start_counter(count: Int) {
  actor.start(count, handle_count)
}

fn stop_counter(counter: process.Subject(Message)) -> Int {
  actor.call(counter, Stop(_), 10)
}

fn handle_count(message: Message, count: Int) {
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
