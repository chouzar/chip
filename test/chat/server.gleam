import chat/event
import chat/pubsub
import gleam/erlang/process
import gleam/option
import gleam/otp/actor
import gleam/otp/supervisor
import gleam/result

pub type Server =
  process.Subject(Message)

pub fn start(pubsub: pubsub.PubSub) -> Result(Server, actor.StartError) {
  let init = fn() { init(pubsub) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

pub fn childspec(caller: process.Subject(Server)) {
  supervisor.worker(fn(pubsub) {
    use server <- result.try(start(pubsub))
    process.send(caller, server)
    Ok(server)
  })
}

pub fn connect(server: Server, client: process.Subject(event.Event)) -> Nil {
  actor.send(server, Connect(client))
}

pub fn send(server: Server, user: String, message: String) -> Nil {
  actor.send(server, Send(user, message))
}

pub opaque type Message {
  Connect(client: process.Subject(event.Event))
  Send(user: String, message: String)
}

type State {
  State(pubsub: pubsub.PubSub, chat: List(event.Event))
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
      let event = event.next(state.chat, user, message)
      let chat = [event, ..state.chat]

      pubsub.publish(state.pubsub, event)
      let state = State(..state, chat: chat)
      actor.Continue(state, option.None)
    }
  }
}
