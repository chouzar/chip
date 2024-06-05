import chat/event.{type Message}
import chat/server
import gleam/erlang/process
import gleam/function
import gleam/int
import gleam/list
import gleam/option
import gleam/otp/actor

pub type Client =
  process.Subject(Message)

// TODO: We just need the Receive constructor to be separate
type State {
  State(
    self: Client,
    server: server.Server,
    name: String,
    messages: List(String),
  )
}

pub fn start(
  server: server.Server,
  name: String,
) -> Result(Client, actor.StartError) {
  let init = fn() { init(server, name) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

pub fn child_spec() {
  todo
}

pub fn send(client: Client, message: String) -> Nil {
  actor.send(client, event.Send(message))
}

pub fn chat(client: Client) -> List(String) {
  actor.call(client, event.Chat(_), 10)
}

fn init(server: server.Server, name: String) {
  let self = process.new_subject()
  server.connect(server, self, name)
  let state = State(self: self, server: server, name: name, messages: [])
  actor.Ready(
    state,
    process.new_selector() |> process.selecting(self, function.identity),
  )
}

fn loop(message: Message, state: State) {
  case message {
    event.Send(message) -> {
      server.send(state.server, state.name, message)
      actor.Continue(state, option.None)
    }

    event.Receive(event) -> {
      let message = build_message(event)
      let messages = [message, ..state.messages]
      let state = State(..state, messages: messages)
      actor.Continue(state, option.None)
    }

    event.Chat(client) -> {
      let messages = list.reverse(state.messages)
      actor.send(client, messages)
      actor.Continue(state, option.None)
    }
  }
}

fn build_message(event: event.Event) -> String {
  let id = int.to_string(event.id)
  id <> " " <> event.user <> ": " <> event.message
}
