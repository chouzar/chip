import chat/event
import chip/group
import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervisor

pub type PubSub =
  process.Subject(group.Message(Channel, event.Event))

pub type Channel {
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

pub fn subscribe(
  pubsub: PubSub,
  channel: Channel,
  subject: process.Subject(event.Event),
) -> Nil {
  group.register(pubsub, subject, channel)
}

pub fn publish(pubsub: PubSub, channel: Channel, message: event.Event) -> Nil {
  group.dispatch(pubsub, channel, fn(subscriber) {
    process.send(subscriber, message)
  })
}
