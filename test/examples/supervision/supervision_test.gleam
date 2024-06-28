import chip
import gleam/erlang/process
import gleam/function
import gleam/otp/actor
import gleam/otp/supervisor
import gleam/result.{try}

pub fn main_test() {
  // launch the supervisor and wait to receive the registry's subject
  let self = process.new_subject()
  let Nil = supervisor(self)
  let assert Ok(registry) = process.receive(self, 50)

  // retrieve the counter's subject, and operate on it
  let assert Ok(counter) = chip.find(registry, 1)

  // lets attempt to restart it and wait for the registry to update
  process.send(counter, Oops)

  eventually_assert(for: 50, try: fn() {
    case chip.find(registry, 1) {
      Ok(c) if c != counter -> True
      _else -> False
    }
  })
}

fn supervisor(caller) {
  let childspec_registry = fn(_param) {
    use registry <- try(chip.start())
    // on success, send the registry back to caller.
    process.send(caller, registry)
    Ok(registry)
  }

  // Transform initial child parameter to the registry and an id tag
  let updater_registry = fn(_param, registry) { #(registry, 1) }

  let childspec_counter = fn(param) {
    // We now receive the registry and initial id
    let #(registry, id) = param
    start(registry, id)
  }

  // Subsequent child counters will increment their id tag
  let updater_counter = fn(param, _counter) {
    let #(registry, id) = param
    #(registry, id + 1)
  }

  // start all processess under a supervision tree 
  let assert Ok(_supervisor) =
    supervisor.start(fn(children) {
      children
      |> supervisor.add(
        supervisor.worker(childspec_registry)
        |> supervisor.returning(updater_registry),
      )
      |> supervisor.add(
        supervisor.worker(childspec_counter)
        |> supervisor.returning(updater_counter),
      )
    })

  Nil
}

// ---------- Counter actor logic ----------

pub opaque type Message {
  Inc
  Oops
}

pub fn start(registry, tag) {
  let init = fn() { init(registry, tag) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

fn init(registry, id) {
  // Create a reference to self
  let self = process.new_subject()

  // Register the counter under an id on initialization
  chip.register(
    registry,
    self
      |> chip.new()
      |> chip.tag(id),
  )

  // Adding self to the selector allows us to receive the Stop message
  actor.Ready(
    0,
    process.new_selector()
      |> process.selecting(self, function.identity),
  )
}

fn loop(message: Message, count: Int) {
  case message {
    Inc -> actor.continue(count + 1)
    Oops -> actor.Stop(process.Normal)
  }
}

// ---------- Test helpers ----------

fn eventually_assert(for milliseconds: Int, try condition: fn() -> Bool) -> Nil {
  case milliseconds, condition() {
    milliseconds, False if milliseconds == 0 -> {
      panic as "timeout"
    }

    _milliseconds, False -> {
      process.sleep(5)
      eventually_assert(milliseconds - 5, condition)
    }

    _milliseconds, True -> {
      Nil
    }
  }
}
