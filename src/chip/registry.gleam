////Chip is a gleam process registry that plays along the [Gleam Erlang](https://hexdocs.pm/gleam_erlang/) `Subject` type. 
////
////It lets tag subjects under a name or group to later reference them. Will also automatically delist dead processes.

import gleam/dict.{type Dict}
import gleam/erlang/process.{
  type Pid, type ProcessDown, type ProcessMonitor, type Selector, type Subject,
}
import gleam/function
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/set.{type Set}

type Registry(name, message) =
  Subject(Message(name, message))

/// This is the message type used internally by group. 
/// 
/// When building out your system it may be useful to state the group types on startup. For example: 
/// 
/// ```gleam
/// let assert Ok(registry) = registry.start()
/// let registry: process.Subject(registry.Message(String, User))
/// ```
/// 
/// By specifying the types we can document the kind of registry we are working with; in the example
/// above we can tell we're creating different "users" with unique stringified names.
pub opaque type Message(name, msg) {
  Tag(client: Subject(Result(Subject(msg), Nil)), name: name)
  Registrant(subject: Subject(msg), name: name)
  Demonitor(index: Index)
}

type Index {
  Index(pid: Pid, monitor: ProcessMonitor)
}

type State(name, msg) {
  State(
    // A reference to the actor's subject.
    self: Registry(name, msg),
    // This tags a subject under a unique name.
    names: Dict(name, Subject(msg)),
    // Index to help track monitored subjects and where to look on de-registration.
    subject_track: Dict(Pid, Set(name)),
    // There's no way of retrieving previous selector from current process, so we manually track it here.
    selector: Selector(Message(name, msg)),
  )
}

/// Starts the registry.
/// 
/// ## Example
/// 
/// ```gleam
/// > registry.start()
/// Ok(registry)
/// ```
pub fn start() -> Result(Registry(name, msg), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: handle_init,
    init_timeout: 10,
    loop: handle_message,
  ))
}

/// Registers a `Subject` under a unique name. 
/// 
/// ## Example
/// 
/// ```gleam
/// > registry.register(registry, process.new_subject(), "my-subject")
/// Nil
/// ```
pub fn register(
  registry: Subject(Message(name, message)),
  subject: Subject(message),
  name: name,
) -> Nil {
  process.send(registry, Registrant(subject, name))
}

/// Looks up a uniquely named `Subject`.
/// 
/// ### Example
/// 
/// ```gleam
/// > registry.find(registry, "my-subject") 
/// Ok(subject)
/// ```
pub fn find(registry, name) -> Result(Subject(msg), Nil) {
  process.call(registry, Tag(_, name), 10)
}

fn handle_init() {
  let self = process.new_subject()

  let state =
    State(
      self: self,
      names: dict.new(),
      subject_track: dict.new(),
      selector: process.new_selector()
        |> process.selecting(self, function.identity),
    )

  actor.Ready(state, state.selector)
}

fn handle_message(message: Message(name, message), state: State(name, message)) {
  case message {
    Tag(client, name) -> {
      let result = dict.get(state.names, name)
      process.send(client, result)
      actor.continue(state)
    }

    Registrant(subject, name) -> {
      let pid = process.subject_owner(subject)
      let selection = monitor(state, pid)

      state
      |> into_names(name, subject)
      |> into_tracker(pid, name)
      |> into_selector(selection)
      |> actor.Continue(selection)
    }

    Demonitor(Index(pid, monitor)) -> {
      process.demonitor_process(monitor)

      state
      |> remove_from_group(pid)
      |> remove_from_tracker(pid)
      |> actor.continue()
    }
  }
}

fn into_names(
  state: State(name, msg),
  name: name,
  subject: Subject(msg),
) -> State(name, msg) {
  State(..state, names: dict.insert(state.names, name, subject))
}

fn into_tracker(
  state: State(name, msg),
  pid: Pid,
  location: name,
) -> State(name, msg) {
  let add_location = fn(option) {
    case option {
      Some(locations) -> set.insert(locations, location)
      None -> set.insert(set.new(), location)
    }
  }

  State(
    ..state,
    subject_track: dict.update(state.subject_track, pid, add_location),
  )
}

fn into_selector(
  state: State(name, msg),
  selection: Option(Selector(Message(name, msg))),
) -> State(name, msg) {
  case selection {
    Some(selector) -> State(..state, selector: selector)
    None -> state
  }
}

fn remove_from_group(state: State(name, msg), pid: Pid) -> State(name, msg) {
  let names = case dict.get(state.subject_track, pid) {
    Ok(locations) -> {
      set.to_list(locations)
    }
    Error(Nil) -> {
      panic as "Impossible state, couldn't find a pid when removing from group."
    }
  }

  list.fold(names, state, fn(state, name) {
    let names = dict.delete(state.names, name)
    State(..state, names: names)
  })
}

fn remove_from_tracker(state: State(name, msg), pid: Pid) -> State(name, msg) {
  State(..state, subject_track: dict.delete(state.subject_track, pid))
}

fn monitor(
  state: State(name, msg),
  pid: Pid,
) -> Option(Selector(Message(name, msg))) {
  // Check if this process is already registered.
  case dict.get(state.subject_track, pid) {
    Ok(_locations) -> {
      // When process is already registered do nothing.
      None
    }

    Error(Nil) -> {
      // When it is a new process, monitor it.
      let monitor = process.monitor_process(pid)
      let selector = select_process_down(state.selector, pid, monitor)
      Some(selector)
    }
  }
}

fn select_process_down(
  selector: Selector(Message(name, msg)),
  pid: Pid,
  monitor: ProcessMonitor,
) -> Selector(Message(name, msg)) {
  // Build the selector with an index to track down the location of subjects 
  // when a the process goes down.
  let index = Index(pid, monitor)
  let handle = fn(_: ProcessDown) { Demonitor(index) }
  process.selecting_process_down(selector, monitor, handle)
}
