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

  chip.group(registry, c1, GroupA)
  chip.group(registry, c2, GroupB)
  chip.group(registry, c3, GroupB)
  chip.group(registry, c4, GroupC)
  chip.group(registry, c5, GroupC)
  chip.group(registry, c6, GroupC)

  Context(registry, c1, c2, c3, c4, c5, c6)
}

pub fn start_test() {
  let assert Ok(_registry) = chip.start()
}

pub fn find_test() {
  let setup = fn() -> Context {
    let context = setup()

    chip.register(context.registry, context.counter_1, "1")
    chip.register(context.registry, context.counter_2, "2")
    chip.register(context.registry, context.counter_3, "3")

    context
  }

  describe("can find a named subject", setup, fn(context) {
    let assert Ok(_counter_1) = chip.find(context.registry, "1")
    let assert Ok(_counter_2) = chip.find(context.registry, "2")
    let assert Ok(_counter_3) = chip.find(context.registry, "3")
  })

  describe("unable to find a name not tied to a subject", setup, fn(context) {
    let assert Error(Nil) = chip.find(context.registry, "counter-0")
    let assert Error(Nil) = chip.find(context.registry, "counter-5")
  })
}

pub fn members_test() {
  let setup = fn() -> Context {
    let context = setup()

    chip.group(context.registry, context.counter_1, GroupA)
    chip.group(context.registry, context.counter_2, GroupB)
    chip.group(context.registry, context.counter_3, GroupB)
    chip.group(context.registry, context.counter_4, GroupC)
    chip.group(context.registry, context.counter_5, GroupC)
    chip.group(context.registry, context.counter_6, GroupC)

    context
  }

  describe("can find all members of each group", setup, fn(context) {
    let assert [_] = chip.members(context.registry, GroupA)
    let assert [_, _] = chip.members(context.registry, GroupB)
    let assert [_, _, _] = chip.members(context.registry, GroupC)
    let assert [] = chip.members(context.registry, GroupD)
    let assert [] = chip.members(context.registry, GroupE)
  })
}

/// Test Helpers to setup and tag a test.
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
