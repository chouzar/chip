import chat/event
import chat/pubsub
import chat/server
import chat/supervisor as chat_supervisor
import gleam/erlang/process
import gleam/list
import gleam/otp/task

pub fn chat_test() {
  // Start the chat's supervision tree and retrieve the server.
  let caller: process.Subject(server.Server) = process.new_subject()
  let assert Ok(_supervisor) = chat_supervisor.start(caller)
  let assert Ok(server) = process.receive(caller, 100)

  // For this scenario, out of simplicity, the client is the current process.
  let client_a: Client = process.new_subject()
  let client_b: Client = process.new_subject()

  // Connect the client so it can receive new messages from the server.
  server.connect(server, client_a, pubsub.General)
  server.connect(server, client_b, pubsub.Coffee)
  server.connect(server, client_b, pubsub.Pets)

  task.async(fn() {
    // Send messages from another Subject.
    server.send(server, pubsub.Coffee, "roberto", "Hey!")
    server.send(server, pubsub.General, "luis", "Hola Juan.")
    server.send(server, pubsub.Coffee, "roberto", "Busco recetas para café.")
    server.send(server, pubsub.General, "juan", "Hola Luis, como vas?")
    server.send(server, pubsub.Coffee, "francisco", "¿Qué método?")
    server.send(server, pubsub.Pets, "roberto", "Mi gato 🐈 ♡")
    server.send(server, pubsub.General, "luis", "Bien! Recibiendo mensajes.")
    server.send(server, pubsub.Pets, "anonymous", "owwww! ♡ ♡ ♡")
    server.send(server, pubsub.Coffee, "roberto", "Para dripper.")
  })

  // Client should have received the messages
  let assert [
    "luis: Hola Juan.",
    "juan: Hola Luis, como vas?",
    "luis: Bien! Recibiendo mensajes.",
  ] = wait_for_messages(client_a, [])

  // Client should have received the messages
  let assert [
    "roberto: Hey!",
    "roberto: Busco recetas para café.",
    "francisco: ¿Qué método?",
    "roberto: Mi gato 🐈 ♡",
    "anonymous: owwww! ♡ ♡ ♡",
    "roberto: Para dripper.",
  ] = wait_for_messages(client_b, [])
}

// Client helpers

type Client =
  process.Subject(event.Event)

fn wait_for_messages(client: Client, messages: List(String)) -> List(String) {
  let selector =
    process.new_selector()
    |> process.selecting(client, build_message)

  case process.select(selector, 100) {
    Ok(message) ->
      message
      |> list.prepend(messages, _)
      |> wait_for_messages(client, _)

    Error(Nil) ->
      messages
      |> list.reverse()
  }
}

fn build_message(event: event.Event) -> String {
  event.user <> ": " <> event.message
}
