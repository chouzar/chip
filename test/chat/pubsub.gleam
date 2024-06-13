import chip/group
import gleam/erlang/process
import gleam/otp/actor

pub type PubSub =
  process.Subject(group.Message(Nil, Event))

pub type Client =
  process.Subject(Event)

pub type Event {
  Event(id: Int, user: String, message: String)
}

pub fn start() -> Result(PubSub, actor.StartError) {
  group.start()
}

pub fn subscribe(pubsub: PubSub, subject: process.Subject(Event)) -> Nil {
  group.register(pubsub, subject, Nil)
}

pub fn publish(pubsub: PubSub, message: Event) -> Nil {
  group.dispatch(pubsub, Nil, fn(subscriber) {
    process.send(subscriber, message)
  })
}
