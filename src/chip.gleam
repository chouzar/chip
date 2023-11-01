import gleam/io
import gleam/map.{Map}
import gleam/erlang/process.{ProcessDown, ProcessMonitor, Subject}
import gleam/otp/actor.{StartError}

pub fn main() {
  io.println("Hello from chip!")
}

pub opaque type Message(name, message) {
  Register(name: name, subject: Subject(message))
  Unregister(name: name)
  Find(client: Subject(Result(Subject(message), Errors)), name: name)
}

pub opaque type Record(message) {
  Record(subject: Subject(message), monitor: ProcessMonitor)
}

pub type Errors {
  // TODO: NameTaken
  NotFound
}

pub fn start() -> Result(Subject(Message(name, message)), StartError) {
  actor.start(map.new(), handle_message)
}

pub fn register(registry, name: name, subject: Subject(message)) -> Nil {
  process.send(registry, Register(name, subject))
}

pub fn unregister(registry, name: name) -> Nil {
  process.send(registry, Unregister(name))
}

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
      let handle_down = fn(_down: ProcessDown) { Unregister(name) }

      let handle_process_down =
        process.new_selector()
        |> process.selecting_process_down(monitor, handle_down)

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
