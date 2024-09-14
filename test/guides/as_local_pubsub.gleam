import artifacts/pubsub
import chip
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/task

pub type Channel {
  General
  Coffee
  Pets
}

pub type Event {
  Event(id: Int, message: String)
}

pub fn main() {
  let assert Ok(pubsub) = pubsub.start()

  // for this scenario, out of simplicity, all clients are the current process.
  let client = process.new_subject()

  // client is interested in coffee and pets
  chip.register(pubsub, chip.new(client) |> chip.group(Coffee))
  chip.register(pubsub, chip.new(client) |> chip.group(Pets))

  // lets assume this is the server process broadcasting a welcome message
  task.async(fn() {
    chip.dispatch_group(pubsub, General, fn(client) {
      Event(id: 1, message: "Welcome to General! Follow rules and be nice.")
      |> process.send(client, _)
    })
    chip.dispatch_group(pubsub, Coffee, fn(client) {
      Event(id: 2, message: "Ice breaker! Favorite cup of coffee?")
      |> process.send(client, _)
    })
    chip.dispatch_group(pubsub, Pets, fn(client) {
      Event(id: 3, message: "Pets!")
      |> process.send(client, _)
    })
  })

  // it is then each client's responsability to listen to incoming messages

  // client only receives coffee and pets messages
  let assert True =
    listen_for_messages(client, [])
    |> list.all(fn(message) {
      case message {
        "2: Ice breaker! Favorite cup of coffee?" -> True
        "3: Pets!" -> True
        _other -> False
      }
    })
}

fn listen_for_messages(client, messages) -> List(String) {
  // this function will listen until messages stop arriving for 100 milliseconds

  // a selector is useful to transform our Events into types a client expects (String).
  let selector =
    process.new_selector()
    |> process.selecting(client, to_string)

  case process.select(selector, 100) {
    Ok(message) ->
      // a message was received, capture it and attempt to listen for another message
      message
      |> list.prepend(messages, _)
      |> listen_for_messages(client, _)

    Error(Nil) ->
      // a message was not received, stop listening and return captured messages in order
      messages
      |> list.reverse()
  }
}

fn to_string(event: Event) -> String {
  int.to_string(event.id) <> ": " <> event.message
}
