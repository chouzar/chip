import chip
import examples/data_modelling/chat/event
import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervisor

pub type PubSub =
  chip.Registry(event.Event, Nil, Channel)

pub type Channel {
  General
  Coffee
  Pets
}

pub fn start() -> Result(PubSub, actor.StartError) {
  chip.start()
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
  chip.new(subject)
  |> chip.group(channel)
  |> chip.register(pubsub, _)
}

pub fn publish(pubsub: PubSub, channel: Channel, message: event.Event) -> Nil {
  chip.dispatch_group(pubsub, channel, fn(subscriber) {
    process.send(subscriber, message)
  })
}
