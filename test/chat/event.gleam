import gleam/erlang/process

pub type Event {
  Event(id: Int, user: String, message: String)
}

pub type Message {
  Send(message: String)
  Receive(event: Event)
  Chat(client: process.Subject(List(String)))
}
