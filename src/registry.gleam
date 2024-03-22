import gleam/set.{type Set}
import gleam/dict.{type Dict}
import gleam/option.{None, Some}
import gleam/erlang.{type Reference}
import gleam/erlang/process.{
  type Pid, type ProcessDown, type ProcessMonitor, type Selector, type Subject,
}
import gleam/otp/actor
import gleam/io

type Registry(name, message) =
  Subject(Message(name, message))

pub opaque type Message(name, mssg) {
  Names(client: Subject(List(name)))
  NamedContent(client: Subject(Result(Subject(mssg), Nil)), name: name)
  UniqueRegistrant(subject: Subject(mssg), name: name)
  Demonitor(pid: Pid)
}

type State(name, mssg) {
  State(
    // This tags a subject reference under a unique name.
    subjects: Dict(name, Subject(mssg)),
    // When adding or de-registering, its useful to have quick access to the monitor ref and names.
    monitors: Dict(Pid, #(ProcessMonitor, Set(name))),
    // There's no way of retrieving previous selector from current process, so we manually track it here.
    selector: Selector(Message(name, mssg)),
  )
}

pub fn start() -> Result(Registry(name, mssg), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: handle_init,
    init_timeout: 10,
    loop: handle_message,
  ))
}

pub fn registered_names(registry) -> List(name) {
  process.call(registry, Names(_), 10)
}

pub fn find_subject(registry, name) -> Result(Subject(mssg), Nil) {
  process.call(registry, NamedContent(_, name), 10)
}

pub fn register(
  registry: Subject(Message(name, message)),
  subject: Subject(message),
  name: name,
) -> Nil {
  process.send(registry, UniqueRegistrant(subject, name))
}

fn handle_init() -> actor.InitResult(
  State(name, message),
  Message(name, message),
) {
  let selector = process.new_selector()
  let state =
    State(subjects: dict.new(), monitors: dict.new(), selector: selector)

  actor.Ready(state, selector)
}

fn handle_message(message: Message(name, message), state: State(name, message)) {
  case message {
    Names(client) -> {
      let names = dict.keys(state.subjects)
      process.send(client, names)
      actor.continue(state)
    }

    NamedContent(client, name) -> {
      let result = dict.get(state.subjects, name)
      process.send(client, result)
      actor.continue(state)
    }

    UniqueRegistrant(subject, name) -> {
      // Check if this subject is already registered.
      let pid = process.subject_owner(subject)
      let record = case dict.get(state.monitors, pid) {
        Ok(#(monitor, names)) -> {
          // If subject is already registered do nothing.
          #(monitor, names, state.selector, None)
        }

        Error(Nil) -> {
          // If subject is a new process, monitor it.
          let monitor = process.monitor_process(pid)
          let names = set.new()

          // Build the selector to track down if monitored process goes down
          let handle = fn(_process: ProcessDown) { Demonitor(pid) }
          let selector =
            process.selecting_process_down(state.selector, monitor, handle)

          #(monitor, names, selector, Some(selector))
        }
      }

      // Store the new monitors, subjects and selector as a reference.
      let #(monitor, names, selector, selection) = record
      let subjects = dict.insert(state.subjects, name, subject)
      let monitors =
        dict.insert(state.monitors, pid, #(monitor, set.insert(names, name)))

      actor.Continue(State(subjects, monitors, selector), selection)
    }

    Demonitor(pid) -> {
      case dict.get(state.monitors, pid) {
        Ok(#(monitor, names)) -> {
          // Demonitor process
          process.demonitor_process(monitor)

          // Delete the monitors and subjects references.
          let subjects = set.fold(names, state.subjects, dict.delete)
          let monitors = dict.delete(state.monitors, pid)

          let state = State(..state, subjects: subjects, monitors: monitors)
          actor.continue(state)
        }

        Error(Nil) -> {
          io.print("pid was not in registry")
          io.debug(pid)

          actor.continue(state)
        }
      }
    }
  }
}
