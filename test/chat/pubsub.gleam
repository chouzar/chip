import chat/event
import chip/group
import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervisor

pub type PubSub =
  process.Subject(group.Message(Nil, event.Event))

// TODO: Maybe do channels for a more complex use case
type Channel {
  General
  Coffee
  Pets
}

pub fn start() -> Result(PubSub, actor.StartError) {
  group.start()
}

pub fn childspec() {
  supervisor.worker(fn(_param) { start() })
  |> supervisor.returning(fn(_param, pubsub) { pubsub })
}

pub fn subscribe(pubsub: PubSub, subject: process.Subject(event.Event)) -> Nil {
  group.register(pubsub, subject, Nil)
}

pub fn publish(pubsub: PubSub, message: event.Event) -> Nil {
  group.dispatch(pubsub, Nil, fn(subscriber) {
    process.send(subscriber, message)
  })
}
