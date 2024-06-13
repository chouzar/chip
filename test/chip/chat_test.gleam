import chat/pubsub
import chat/server
import gleam/erlang/process
import gleam/list

pub fn chat_test() {
  // Good Example to start the supervision example maybe is to do it without.
  // Another good example is order dependency vs inheritance.
  let assert Ok(pubsub) = pubsub.start()
  let assert Ok(server) = server.start(pubsub)

  let self: pubsub.Client = process.new_subject()

  server.connect(server, self)

  server.send(server, "luis", "Hola Juan")
  server.send(server, "juan", "Hola Luis, como vas?")
  server.send(server, "luis", "Bien! Estas recibiendo mensajes")

  let assert [
    "luis: Hola Juan",
    "juan: Hola Luis, como vas?",
    "luis: Bien! Estas recibiendo mensajes",
  ] = wait_for_messages(self, [])
}


fn wait_for_messages(
  subject: process.Subject(pubsub.Event),
  messages: List(String),
) -> List(String) {
  case process.receive(subject, 100) {
    Ok(event) ->
      event
      |> build_message()
      |> list.prepend(messages, _)
      |> wait_for_messages(subject, _)

    Error(Nil) ->
      messages
      |> list.reverse()
  }
}

fn build_message(event: pubsub.Event) -> String {
  event.user <> ": " <> event.message
}
