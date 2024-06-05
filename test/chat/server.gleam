import chat/pubsub
import gleam/erlang/process
import gleam/option
import gleam/otp/actor

pub opaque type Message(client_message) {
  Connect(client: process.Subject(client_message))
  Send(user: String, message: String)
}

pub type Server(client_message) =
  process.Subject(Message(client_message))

type State(client_message) {
  State(pubsub: pubsub.PubSub(client_message), chat: List(Event))
}

pub type Event {
  Event(id: Int, user: String, message: String)
}

pub fn start(
  pubsub: pubsub.PubSub(client_message),
) -> Result(Server(client_message), actor.StartError) {
  let init = fn() { init(pubsub) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

pub fn child_spec() {
  todo
}

pub fn connect(
  server: Server(client_message),
  client: process.Subject(client_message),
) -> Nil {
  actor.send(server, Connect(client))
}

pub fn send(
  server: Server(client_message),
  user: String,
  message: String,
) -> Nil {
  actor.send(server, Send(user, message))
}

fn init(pubsub: pubsub.PubSub(client_message)) {
  let state = State(pubsub: pubsub, chat: [])
  actor.Ready(state, process.new_selector())
}

fn loop(message: Message(client_message), state: State(client_message)) {
  case message {
    Connect(client) -> {
      pubsub.subscribe(state.pubsub, client)
      actor.Continue(state, option.None)
    }

    Send(user, message) -> {
      let id = next_id(state.chat)
      let event = Event(id, user, message)
      let chat = [event, ..state.chat]

      pubsub.publish(state.pubsub, event)
      let state = State(..state, chat: chat)
      actor.Continue(state, option.None)
    }
  }
}

fn next_id(chat: List(Event)) -> Int {
  case chat {
    [] -> 1
    [record, ..] -> record.id + 1
  }
}
