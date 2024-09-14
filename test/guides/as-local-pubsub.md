# Chip as your local PubSub system

A PubSub will allow us to "subscribe" subjects to a "topic", then later we we can "publish" an event to all subscribed subjects. 

```gleam
import chip
import gleam/erlang/process
import gleam/otp/supervisor

pub type PubSub(message, channel) =
  chip.Registry(message, Nil, channel)

pub fn start() {
  chip.start()
}

pub fn childspec() {
  supervisor.worker(fn(_param) { start() })
  |> supervisor.returning(fn(_param, pubsub) { pubsub })
}

pub fn subscribe(
  pubsub: PubSub(message, channel),
  channel: channel,
  subject: process.Subject(message),
) -> Nil {
  chip.new(subject)
  |> chip.group(channel)
  |> chip.register(pubsub, _)
}

pub fn publish(
  pubsub: PubSub(message, channel),
  channel: channel,
  message: message,
) -> Nil {
  chip.dispatch_group(pubsub, channel, fn(subscriber) {
    process.send(subscriber, message)
  })
}
```

The pattern above would be a generic way of re-defining chip as a pubsub system, we may use it to wire-up applications that require reacting to events. For example, lets assume we want to create a chat application.  

```gleam 
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
```

There are many ways to structure a PubSub system in Gleam so this guide is just a starting point. 

While building your system with a PubSub you may start getting into clashes between modules (gleam doesn't like circular dependencies), if you find yourself in this situation try to:

* Divide shared types, for example put `Event` in its own module.  
* Take advantage of generics so you don't have to be bound to specific types.
* Take advantage of callbacks so you don't have to be bound to specific behaviour.

As a final tip, sometimes we may try to optimize the project structure too early, if in doubt try to keep your types and functions in one module and separate as your abstractions and domain knowledge mature.
