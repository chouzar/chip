//// A pure gleam process registry that plays along types and gleam OTP abstractions.
//// Will automatically delist dead processes. 
//// 
//// ## Example
//// 
//// ```gleam
//// import gleam/erlang/process
//// import chip
//// 
//// // Names can be built out of any primitive or even types.
//// type Name {
////   A
////   B
//// }
////
//// // We can start the registry and register a new subject 
//// let assert Ok(registry) = chip.start()
//// chip.register(registry, A, process.new_subject())
//// 
//// // If we lose scope of our processes, just look it up in the registry!
//// let assert Ok(subject) = chip.find(registry, A)
//// let assert Error(chip.NotFound) = chip.find(registry, B)
//// ```

import gleam/list
import gleam/map.{Map}
import gleam/erlang/process.{ProcessDown, ProcessMonitor, Selector, Subject}
import gleam/otp/actor.{StartError}

/// These are the possible messages that our registry can handle, this is an opaque
/// type so you would use these commands through the equivalent functions.
pub opaque type Message(name, message) {
  Register(name: name, subject: Subject(message))
  Unregister(name: name)
  Find(client: Subject(Result(Subject(message), Errors)), name: name)
}

type Record(message) {
  Record(subject: Subject(message), monitor: ProcessMonitor)
}

pub type Errors {
  // TODO: NameTaken
  NotFound
}

/// Starts our registry.
/// 
/// ## Example
/// 
/// ```gleam
/// > chip.start()
/// Ok(registry)
/// ```
pub fn start() -> Result(Subject(Message(name, message)), StartError) {
  // TODO: Maybe a phatom type to delineate the name type would be useful
  actor.start(map.new(), handle_message)
}

/// Manually registers a `Subject` within the registry.
/// 
/// ## Example
/// 
/// ```gleam
/// > chip.register(registry, "MyProcess", process.new_subject())
/// Nil
/// ```
pub fn register(registry, name: name, subject: Subject(message)) -> Nil {
  process.send(registry, Register(name, subject))
}

/// Manually unregister a `Subject` within the registry.
/// 
/// ## Example
/// 
/// ```gleam
/// > chip.unregister(registry, "MyProcess")
/// Nil
/// ```
pub fn unregister(registry, name: name) -> Nil {
  process.send(registry, Unregister(name))
}

/// Looks up a subject through its given name.
/// 
/// ### Example
/// 
/// ```gleam
/// > chip.find(reigstry, "MyProcess") 
/// Ok(subject)
/// ```
pub fn find(registry, name: name) -> Result(Subject(message), Errors) {
  process.call(registry, fn(self) { Find(self, name) }, 100)
}

fn handle_message(
  message: Message(name, subject_message),
  state: Map(name, Record(subject_message)),
) {
  case message {
    Register(name, subject) -> {
      // Start monitoring the pid within this process
      let monitor =
        subject
        |> process.subject_owner()
        |> process.monitor_process()

      // TODO: temporarily stored internally here.
      // Eventually dispatch to a store (GenServer, ets, DB)
      let state = map.insert(state, name, Record(subject, monitor))

      // When a process down message is received map it to an unregister message
      let handle_process_down =
        state
        |> map.to_list()
        |> list.fold(process.new_selector(), build_handle_down)

      // Continue with handle down selector
      actor.continue(state)
      |> actor.with_selector(handle_process_down)
    }

    Unregister(name) -> {
      case map.get(state, name) {
        Ok(Record(_subject, monitor)) -> {
          process.demonitor_process(monitor)
          let state = map.delete(state, name)
          actor.continue(state)
        }

        Error(Nil) -> {
          actor.continue(state)
        }
      }
    }

    Find(client, name) -> {
      case map.get(state, name) {
        Ok(Record(subject, _monitor)) -> {
          process.send(client, Ok(subject))
          actor.continue(state)
        }

        Error(Nil) -> {
          process.send(client, Error(NotFound))
          actor.continue(state)
        }
      }
    }
  }
}

fn build_handle_down(
  selector: Selector(Message(name, subject_message)),
  name_record: #(name, Record(message)),
) {
  let name = name_record.0
  let Record(_subject, monitor) = name_record.1

  let handle_down = fn(_down: ProcessDown) { Unregister(name) }
  process.selecting_process_down(selector, monitor, handle_down)
}
