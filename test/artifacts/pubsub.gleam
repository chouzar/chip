import chip
import gleam/erlang/process
import gleam/otp/supervisor

pub type PubSub(message, channel) =
  chip.Registry(message, Nil, channel)

pub fn start() {
  chip.start()
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
  chip.new(subject)
  |> chip.group(channel)
  |> chip.register(pubsub, _)
}

pub fn publish(
  pubsub: PubSub(message, channel),
  channel: channel,
  message: message,
) -> Nil {
  chip.dispatch_group(pubsub, channel, fn(subscriber) {
    process.send(subscriber, message)
  })
}
