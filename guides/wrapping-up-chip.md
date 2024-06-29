# Wrapping up chip

It is not a bad idea to wrap chip around your particular use-case, it is not exhaustive but here I try to show the general idea on how to specialize chip into a process index, a pubsub or app configuration. 

## A process index module

The main purpose of the process index is to be able to "track" individual subjects through an identifier in your system. The identifier may be an integer, string or even a union type if you only need few records.

```gleam
import chip
import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervisor

pub type Store(message) =
  chip.Registry(message, Int, Nil)

pub type Id =
  Int

pub fn start() -> Result(Store(message), actor.StartError) {
  chip.start()
}

pub fn childspec() {
  supervisor.worker(fn(_index) { start() })
}

pub fn index(store: Store(message), id: Id, subject: process.Subject(message)) {
  chip.new(subject)
  |> chip.tag(id)
  |> chip.register(store, _)
}

pub fn get(store: Store(message), id: Id) {
  chip.find(store, id)  
}
```

## A PubSub module

A PubSub will allow us to "subscribe" subjects to `chip` to later "publish" events. It will be the responsability of the clients to capture and process these messages.

```gleam
import chip
import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervisor

pub type PubSub(message) =
  chip.Registry(message, Nil, Channel)

pub type Channel {
  General
  Coffee
  Pets
}

pub fn start() -> Result(PubSub(message), actor.StartError) {
  chip.start()
}

pub fn childspec() {
  supervisor.worker(fn(_param) { start() })
  |> supervisor.returning(fn(_param, pubsub) { pubsub })
}

pub fn publish(
  pubsub: PubSub(message),
  channel: Channel,
  message: message,
) -> Nil {
  chip.dispatch_group(pubsub, channel, fn(subscriber) {
    process.send(subscriber, message)
  })
}

pub fn subscribe(
  pubsub: PubSub(message),
  channel: Channel,
  subject: process.Subject(message),
) -> Nil {
  chip.new(subject)
  |> chip.group(channel)
  |> chip.register(pubsub, _)
}
```

## Global app configuration 

This is similar to the process index above but tweaked to work as a global app configuration of sorts. 

```gleam
import chip
import gleam/erlang/process
import gleam/otp/actor
import gleam/result.{try}

pub type Config(message) =
  chip.Registry(message, Component, Nil)

pub type Component {
  WebServer
  Sessions
  PubSub
}

pub fn start() -> Result(Config(message), actor.StartError) {
  use config <- try(chip.start())
  global_put(config)
  Ok(config)
}

pub fn add(name component: Component, add subject: process.Subject(message)) {
  let config = global_get()

  chip.new(subject)
  |> chip.tag(component)
  |> chip.register(config, _)
}

pub fn get(component: Component) {
  let config = global_get()

  case chip.find(config, component) {
    Ok(subject) -> {
      subject
    }

    Error(Nil) -> {
      // We may attempt any retry strategy that works for our system. 
      // Here we're allowing ourselves to "let it crash" and expect 
      // the process to eventually be restarted.
      panic as {
        "unable to retrieve requested component: " <> error_msg(component)
      }
    }
  }
}

fn error_msg(component) {
  case component {
    WebServer -> "WebServer"
    Sessions -> "Sessions"
    PubSub -> "PubSub"
  }
}

fn global_put(_config: Config(message)) -> Nil {
  // This global store may be an ETS table or another global process
  todo
}

fn global_get() -> Config(message) {
  // This global store may be an ETS table or another global process
  todo
}
```

Chip may not be as well suited for this purpose as it can only store subjects of a single message type. If you need to reference subjects with different message types you may look at the [singularity](https://hexdocs.pm/singularity/) library.