import chat/client
import chat/event
import chat/pubsub
import chat/server
import gleam/erlang/process

pub fn chat_test() {
  // Good Example to start the supervision exam,ple maybe is to do it without.
  // Another good example is order dependency vs inheritance.
  let assert Ok(pubsub) = pubsub.start()
  let assert Ok(server) = server.start(pubsub)
  let assert Ok(luis) = client.start(server, "Luis")
  let assert Ok(juan) = client.start(server, "Juan")
  let assert Ok(user) = client.start(server, "user")

  client.send(luis, "Hola Juan")
  client.send(juan, "Hola Luis, como vas?")
  client.send(luis, "Bien! Estas recibiendo mensajes")

  process.sleep(500)

  let assert [
    "1 Luis: Hola Juan",
    "2 Juan: Hola Luis, como vas?",
    "3 Luis: Bien! Estas recibiendo mensajes",
  ] = client.chat(user)
}
