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

  // For this scenario, out of simplicity, all clients are the current process.
  let client = process.new_subject()

  // Client is interested in coffee and pets.
  chip.register(pubsub, Coffee, client)
  chip.register(pubsub, Pets, client)

  // Lets assume this is the server process broadcasting a welcome message.
  task.async(fn() {
    chip.members(pubsub, General, 50)
    |> list.each(fn(client) {
      Event(id: 1, message: "Welcome to General! Follow rules and be nice.")
      |> process.send(client, _)
    })
    chip.members(pubsub, Coffee, 50)
    |> list.each(fn(client) {
      Event(id: 2, message: "Ice breaker! Favorite cup of coffee?")
      |> process.send(client, _)
    })
    chip.members(pubsub, Pets, 50)
    |> list.each(fn(client) {
      Event(id: 3, message: "Pets!")
      |> process.send(client, _)
    })
  })

  // It is then each client's responsability to listen to incoming messages,
  // our previous client is only subscribed to coffee and pets, so it only receives those messages.
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
  // This function will listen until messages stop arriving for 100 milliseconds.

  // A selector is useful to transform our Events into types a client expects,
  // in this case the client can only receive String messages so we cast
  // events into strings with the `to_string` function.
  let selector =
    process.new_selector()
    |> process.selecting(client, to_string)

  case process.select(selector, 100) {
    Ok(message) ->
      // A message was received, capture it and attempt to listen for another message.
      message
      |> list.prepend(messages, _)
      |> listen_for_messages(client, _)

    Error(Nil) ->
      // A message was not received, stop listening and return captured messages in order.
      messages
      |> list.reverse()
  }
}

fn to_string(event: Event) -> String {
  int.to_string(event.id) <> ": " <> event.message
}
