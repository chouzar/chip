import chip
import gleam/erlang/process
import gleam/function.{identity}
import gleam/list
import gleam/otp/task

pub fn pubsub_protocol_test() {
  let client_a: process.Subject(String) = process.new_subject()
  let client_b: process.Subject(Java) = process.new_subject()
  let client_c: process.Subject(Pet) = process.new_subject()

  let assert Ok(general) = chip.start()
  let assert Ok(java) = chip.start()
  let assert Ok(pet) = chip.start()

  // register all clients in general 
  chip.register(general, chip.new(client_a))
  chip.register(java, chip.new(client_b))
  chip.register(pet, chip.new(client_c))

  // the server broadcasts coded messages 
  task.async(fn() {
    chip.dispatch(general, fn(client) { process.send(client, "How's everyone") })

    chip.dispatch(java, fn(client) { process.send(client, Brew) })

    chip.dispatch(pet, fn(client) { process.send(client, Meow) })
  })

  // then receive as a single client
  let assert ["How's everyone", "brewing", "meoww"] =
    process.new_selector()
    |> process.selecting(client_a, identity)
    |> process.selecting(client_b, protocol_java)
    |> process.selecting(client_c, protocol_pet)
    |> listen_for_protocol([])
}

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

type Java {
  Brew
  Drip
  Temp
}

fn protocol_java(java: Java) -> String {
  case java {
    Drip -> "to drip"
    Brew -> "brewing"
    Temp -> "at temp"
  }
}

type Pet {
  Woof
  Meow
  Splash
}

fn protocol_pet(noise: Pet) -> String {
  case noise {
    Woof -> "woof!"
    Meow -> "meoww"
    Splash -> ""
  }
}
