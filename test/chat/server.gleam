import chat/pubsub
import gleam/erlang/process
import gleam/option
import gleam/otp/actor

pub opaque type Message {
  Connect(client: pubsub.Client)
  Send(user: String, message: String)
}

pub type Server =
  process.Subject(Message)

type State {
  State(pubsub: pubsub.PubSub, chat: List(pubsub.Event))
}

pub fn start(pubsub: pubsub.PubSub) -> Result(Server, actor.StartError) {
  let init = fn() { init(pubsub) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

pub fn child_spec() {
  todo
}

pub fn connect(server: Server, client: pubsub.Client) -> Nil {
  actor.send(server, Connect(client))
}

pub fn send(server: Server, user: String, message: String) -> Nil {
  actor.send(server, Send(user, message))
}

fn init(pubsub: pubsub.PubSub) {
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
      let event = pubsub.Event(id, user, message)
      let chat = [event, ..state.chat]

      pubsub.publish(state.pubsub, event)
      let state = State(..state, chat: chat)
      actor.Continue(state, option.None)
    }
  }
}

fn next_id(chat: List(pubsub.Event)) -> Int {
  case chat {
    [] -> 1
    [record, ..] -> record.id + 1
  }
}
