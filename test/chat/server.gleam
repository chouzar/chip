import chat/event
import chat/pubsub
import chip/group
import gleam/erlang/process
import gleam/option
import gleam/otp/actor

pub opaque type Message {
  Connect(client: process.Subject(event.Message))
  Send(user: String, message: String)
}

pub type Server =
  process.Subject(Message)

type State {
  State(pubsub: pubsub.PubSub(event.Message), chat: List(event.Event))
}

pub fn start(
  pubsub: pubsub.PubSub(event.Message),
) -> Result(Server, actor.StartError) {
  let init = fn() { init(pubsub) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

pub fn child_spec() {
  todo
}

pub fn connect(
  server: Server,
  client: process.Subject(event.Message),
  user: String,
) -> Nil {
  actor.send(server, Connect(client))
}

pub fn send(server: Server, user: String, message: String) -> Nil {
  actor.send(server, Send(user, message))
}

fn init(pubsub: pubsub.PubSub(event.Message)) {
  let state = State(pubsub: pubsub, chat: [])
  actor.Ready(state, process.new_selector())
}

fn loop(message: Message, state: State) {
  case message {
    Connect(client) -> {
      pubsub.subscribe(state.pubsub, client)
      actor.Continue(state, option.None)
    }

    Send(user, message) -> {
      let id = next_id(state.chat)
      let event = event.Event(id, user, message)
      let chat = [event, ..state.chat]

      pubsub.broadcast(state.pubsub, event.Receive(event))
      let state = State(..state, chat: chat)
      actor.Continue(state, option.None)
    }
  }
}

fn next_id(chat: List(event.Event)) -> Int {
  case chat {
    [] -> 1
    [record, ..] -> record.id + 1
  }
}
