import chip/group
import gleam/erlang/process
import gleam/otp/actor

pub type PubSub(message) =
  process.Subject(group.Message(Nil, message))

pub fn start() -> Result(PubSub(message), actor.StartError) {
  group.start()
}

pub fn subscribe(
  pubsub: PubSub(message),
  subject: process.Subject(message),
) -> Nil {
  group.register(pubsub, subject, Nil)
}

pub fn broadcast(pubsub: PubSub(message), message: message) -> Nil {
  group.dispatch(pubsub, Nil, fn(subscriber) {
    process.send(subscriber, message)
  })
}
