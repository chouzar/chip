import chip
import gleam/erlang/process
import gleam/function.{identity}
import gleam/option
import gleam/otp/actor
import gleam/otp/supervisor

pub opaque type Message {
  Inc
  Current(client: process.Subject(Int))
  Stop
}

pub type Group {
  GroupA
  GroupB
  GroupC
}

pub fn start(
  registry: chip.Registry(Message, Int, Group),
  id: Int,
  group: Group,
  count: Int,
) {
  let init = fn() { init(registry, id, group, count) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

pub fn childspec(count) {
  supervisor.worker(fn(param) {
    let #(registry, id, group) = param
    start(registry, id, group, count)
  })
  |> supervisor.returning(fn(param, _self) {
    let #(registry, id, group) = param
    #(registry, id + 1, group, count)
  })
}

pub fn stop(counter: process.Subject(Message)) -> Nil {
  actor.send(counter, Stop)
}

pub fn increment(counter: process.Subject(Message)) -> Nil {
  actor.send(counter, Inc)
}

pub fn current(counter: process.Subject(Message)) -> Int {
  actor.call(counter, Current(_), 10)
}

fn init(
  registry: chip.Registry(Message, Int, Group),
  id: Int,
  group: Group,
  count: Int,
) {
  // Create a reference to self
  let self = process.new_subject()

  // Register the counter under an id on initialization
  chip.register(
    registry,
    self
      |> chip.new()
      |> chip.tag(id)
      |> chip.group(group),
  )

  // The registry may send messages through the self subject to this actor
  // adding self to this actor selector will allow us to handle those messages.
  actor.Ready(
    count,
    process.new_selector()
      |> process.selecting(self, identity),
  )
}

fn loop(message: Message, count: Int) {
  case message {
    Inc -> {
      actor.Continue(count + 1, option.None)
    }

    Current(client) -> {
      process.send(client, count)
      actor.Continue(count, option.None)
    }

    Stop -> {
      actor.Stop(process.Normal)
    }
  }
}
