# Chip as a local PubSub system

Gleam programs compiling down to erlang are able to take advantage of [erlang's style of concurrency](https://hexdocs.pm/gleam_erlang/), one of the properties of processess is how they communicate with each other through message passing. 

This property can be used to our advantage to design an even-driven system, where actions are not necesarilly imperative and each component in our system can "react" to external events. One useful tool in event-driven systems is to have a PubSub where we can broadcast messages to whatever processess are subscribed to. 

There are many ways to structure a PubSub system in Gleam so this guide is just a starting point. 

## Designing a chat application

Lets assume we want to create a chat application. Different clients may subscribe to one of the different chat topics which we will harcode as a type for simplicity: 

```gleam
type Topic {
  General
  Coffee
  Pets    
}
```

Our clients may be any type of subject we would like to register, again for simplicity lets say that our clients are the "main" process itself: 

```gleam 
pub fn main() {
  let client_a = process.new_subject()
  let client_b = process.new_subject()
  let client_c = process.new_subject()
}
```

Upon starting chip we can start subscribing clients to different topics and sending messages: 

```gleam
pub fn main() {
  let client_a = process.new_subject()
  let client_b = process.new_subject()
  let client_c = process.new_subject()
  
  let assert Ok(pubsub) = chip.start() 

  // client A is only interested in general  
  chip.register(pubsub, chip.new(client_a) |> chip.group(General))

  // client B only cares about coffee
  chip.register(pubsub, chip.new(client_b) |> chip.group(Coffee))

  // client C wants to be everywhere
  chip.register(pubsub, chip.new(client_c) |> chip.group(General))
  chip.register(pubsub, chip.new(client_c) |> chip.group(Coffee))
  chip.register(pubsub, chip.new(client_c) |> chip.group(Pets))
  
  // broadcast a welcome to all subscribed clients
  task.async(fn() {
    // lets assume this is the server process broadcasting a welcome message
    chip.dispatch_group(pubsub, General, fn(client) { process.send(client, "Welcome to General!") })
    chip.dispatch_group(pubsub, General, fn(client) { process.send(client, "Please follow the rules") })
    chip.dispatch_group(pubsub, General, fn(client) { process.send(client, "and be good with each other :)") })

    chip.dispatch_group(pubsub, Coffee, fn(client) { process.send(client, "Ice breaker!")}) 
    chip.dispatch_group(pubsub, Coffee, fn(client) { process.send(client, "Favorite coffee cup?")}) 

    chip.dispatch_group(pubsub, Pets, fn(client) { process.send(client, "Pets!") })
  })
}
```

In theory all of our clients should have already received a welcome message in their inbox, but each client is responsible to capture this message so lets build this functionality: 

```gleam
fn listen_for_messages(client, messages) -> List(String) {
  // this function will listen until messages stop arriving for 100 milliseconds
  case process.receive(client, 100) {
    Ok(message) ->
      // a message was received, capture it and attempt to listen for another message
      message
      |> list.prepend(messages, _)
      |> listen_for_messages(client, _)

    Error(Nil) ->
      // a message was not received, stop listening and return captured messages in order
      messages
      |> list.reverse()
  }
}
```

Then we may use this function to receive messages with each of our clients: 

```gleam
  // client A receives all messages in general
  let assert [
    "Welcome to General!",
    "Please follow the rules",
    "and be good with each other :)",
  ] = listen_for_messages(client_a, [])
  
  // client B receives all messages in coffee
  let assert [
    "Ice breaker!",
    "Favorite coffee cup?",
  ] = listen_for_messages(client_b, [])
  
  // client C receives all messages 
  let assert [
    "Welcome to General!",
    "Please follow the rules",
    "and be good with each other :)",
    "Ice breaker!",
    "Favorite coffee cup?",
    "Pets!",
  ] = listen_for_messages(client_c, [])
```

And with this we have all the components required for a very basic PubSub system that does subscription and topics. 

## A note on data modelling

We may be tempted to look at the example above and try to modularize it in more discreete, single responsability modules. Keep in mind that PubSub systems may spiral out and grow through the entire system, this will likely not be a problem as Gleam (the language) really doesn't like circular dependencies.

For example. If you have a `Server` module and a `PubSub` module the dependency (likely) will go this direction: 

```
Server  -- uses --> PubSub
```  

But lets say that `Server` does define an `Event` type, which is used by the `PubSub` module, now the dependency goes both ways: 

```
Server <-- uses --> PubSub
```  

There are a couple of ways to avoid this: 

* Divide shared types, in this case `Event` in their own module.  
* Take advantage of generics so you don't have to be bound to specific types.
* Take advantage of callback so you don't have to be bound to specific behaviour.

Sometimes managing the above is quite a headache and not worth it, specially when your domain is not so well defined. 

## Not all servers speak in Strings

So far we have assumed that our server, client and PubSub all speak in `String` messages:  

```gleam
// Server speaks in String
process.send(client, "Welcome to General!")

// Client speaks in String
let client_a: process.Subject(String) = process.new_subject()

// PubSub speaks in String
let assert Ok(pubsub) = chip.start()
let pubsub: process.Subject(chip.Message(String, Nil, Topic))
```

What if a single client was listening to multiple servers? Lets say that some servers communicate in `Java` language for sharing coffee jargon: 

```gleam
type Java {
  Brew
  Drip    
  Temp
}
```

While others used `Pet` for added goofiness: 

```gleam
type Pet {
  Woof
  Meow
  Splash    
}
```

These new event types are incompatible to our PubSub but this doesn't mean we can't design a client that listents to theset types of messages; we just need to modify the approach. 

We can create different subjects with their own types: 

```gleam 
let client_a: process.Subject(String) = process.new_subject()
let client_b: process.Subject(Java) = process.new_subject()
let client_b: process.Subject(Pet) = process.new_subject()
```

And (because of Chip's limitations) different pubsubs with their own types also: 

```gleam
type PubSub(message, tag) =
  process.Subject(chip.Message(message, tag, Topic))

let assert Ok(general) = chip.start()
let general: PubSub(String, tag) = general

let assert Ok(java) = chip.start()
let java: PubSub(Java, tag) = java

let assert Ok(pet) = chip.start()
let java: PubSub(Pet, tag) = pet
```

Each pubsub above is designed for a specific server that sends its own type of events: 

```gleam
// the server broadcasts coded messages 
task.async(fn() {
  chip.dispatch(general, fn(client) {
    process.send(client, "How's everyone")
  })
  
  chip.dispatch(java, fn(client) {
    process.send(client, Brew)
  })
  
  chip.dispatch(pet, fn(client) {
    process.send(client, Meow)
  })
})
```

And we can treat our 3 subjects above as a single client by taking advantage of process selectors, lets modify a bit our `listen_for_messages` function: 

```gleam
fn listen_for_protocol(selector, messages) -> List(String) {
  case process.select(selector, 100) {
    Ok(message) ->
      message
      |> list.prepend(messages, _)
      |> listen_for_protocol(selector, _)

    Error(Nil) ->
      messages
      |> list.reverse()
  }
}
```

Finally using a selector, receive all messages as a single client: 

```gleam
// then receive as a single client
let assert ["How's everyone", "brewing", "meoww"] =
  process.new_selector()
  |> process.selecting(client_a, identity)
  |> process.selecting(client_b, protocol_java)
  |> process.selecting(client_c, protocol_pet)
  |> listen_for_protocol([])

fn identity(x: x) -> x {
  x    
}

fn protocol_java(java: Java) -> String {
  case java {
    Drip -> "to drip"
    Brew -> "brewing"
    Temp -> "at temp"
  }
}

fn protocol_pet(noise: Pet) -> String {
  case noise {
    Woof -> "woof!"
    Meow -> "meoww"
    Splash -> ""
  }
}
```

And this would be a way of managing multiple message types from different sources (servers, pubsubs) with a single client. 
