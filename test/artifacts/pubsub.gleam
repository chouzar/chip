import chip
import gleam/erlang/process
import gleam/list
import gleam/otp/supervisor

pub type PubSub(message, channel) =
  chip.Registry(message, channel)

pub fn start() {
  chip.start(chip.Unnamed)
}

pub fn childspec() {
  supervisor.worker(fn(_param) { start() })
  |> supervisor.returning(fn(_param, pubsub) { pubsub })
}

pub fn subscribe(
  pubsub: PubSub(message, channel),
  channel: channel,
  subject: process.Subject(message),
) -> Nil {
  chip.register(pubsub, channel, subject)
}

pub fn publish(
  pubsub: PubSub(message, channel),
  channel: channel,
  message: message,
) -> Nil {
  chip.members(pubsub, channel, 50)
  |> list.each(fn(subscriber) { process.send(subscriber, message) })
}
