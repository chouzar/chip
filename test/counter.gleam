import gleam/erlang/process
import gleam/option
import gleam/otp/actor

pub opaque type Message {
  Inc
  Current(client: process.Subject(Int))
  Stop
}

/// Starts a counter.
pub fn start(count: Int) {
  let init = fn() { actor.Ready(count, process.new_selector()) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

/// Stops the counter.
pub fn stop(counter: process.Subject(Message)) -> Nil {
  actor.send(counter, Stop)
}

/// Increments the counter.
pub fn increment(counter: process.Subject(Message)) -> Nil {
  actor.send(counter, Inc)
}

/// Returns the current counter value.
pub fn current(counter: process.Subject(Message)) -> Int {
  actor.call(counter, Current(_), 10)
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
