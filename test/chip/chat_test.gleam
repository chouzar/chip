import chat/event
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
  let client: Client = process.new_subject()

  // Connect the client so it can receive new messages from the server.
  server.connect(server, client)

  task.async(fn() {
    // Send messages from another Subject.
    server.send(server, "luis", "Hola Juan.")
    server.send(server, "juan", "Hola Luis, como vas?")
    server.send(server, "luis", "Bien! Recibiendo mensajes.")
  })

  // Client should have received the messages
  let assert [
    "luis: Hola Juan.",
    "juan: Hola Luis, como vas?",
    "luis: Bien! Recibiendo mensajes.",
  ] = wait_for_messages(client, [])
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
