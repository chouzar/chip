import chip
import gleam/erlang/process
import gleam/list
import gleam/otp/task

type PubSub =
  process.Subject(chip.Message(String, Nil, Topic))

type Topic {
  General
  Coffee
  Pets
}

pub fn pubsub_test() {
  let client_a = process.new_subject()
  let client_b = process.new_subject()
  let client_c = process.new_subject()

  let assert Ok(pubsub) = chip.start()
  let pubsub: PubSub = pubsub

  // client A is only interested in general  
  chip.register(pubsub, chip.new(client_a) |> chip.group(General))

  // client B only cares about coffee
  chip.register(pubsub, chip.new(client_b) |> chip.group(Coffee))

  // client C wants to be everywhere
  chip.register(pubsub, chip.new(client_c) |> chip.group(General))
  chip.register(pubsub, chip.new(client_c) |> chip.group(Coffee))
  chip.register(pubsub, chip.new(client_c) |> chip.group(Pets))

  // broadcast a welcome to all subscribed clients
  task.async(fn() {
    // lets assume this is the server process broadcasting a welcome message
    chip.dispatch_group(pubsub, General, fn(client) {
      process.send(client, "Welcome to General!")
    })
    chip.dispatch_group(pubsub, General, fn(client) {
      process.send(client, "Please follow the rules")
    })
    chip.dispatch_group(pubsub, General, fn(client) {
      process.send(client, "and be good with each other :)")
    })

    chip.dispatch_group(pubsub, Coffee, fn(client) {
      process.send(client, "Ice breaker!")
    })
    chip.dispatch_group(pubsub, Coffee, fn(client) {
      process.send(client, "Favorite coffee cup?")
    })
    chip.dispatch_group(pubsub, Pets, fn(client) {
      process.send(client, "Pets!")
    })
  })

  let assert [
    "Welcome to General!",
    "Please follow the rules",
    "and be good with each other :)",
  ] = listen_for_messages(client_a, [])

  let assert ["Ice breaker!", "Favorite coffee cup?"] =
    listen_for_messages(client_b, [])

  let assert [
    "Welcome to General!",
    "Please follow the rules",
    "and be good with each other :)",
    "Ice breaker!",
    "Favorite coffee cup?",
    "Pets!",
  ] = listen_for_messages(client_c, [])
}

fn listen_for_messages(client, messages) -> List(String) {
  // this function will listen until messages stop arriving for 100 milliseconds
  case process.receive(client, 100) {
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
