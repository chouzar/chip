//// This module helps group different `Subject`s under a name to later reference or broadcast messages to them. 

import gleam/dict.{type Dict}
import gleam/erlang/process.{
  type Pid, type ProcessDown, type ProcessMonitor, type Selector, type Subject,
}
import gleam/function
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/set.{type Set}

type Registry(group, message) =
  Subject(Message(group, message))

/// This is the message type used internally by group. 
/// 
/// When building out your system it may be useful to state the group types on startup. For example: 
/// 
/// ```gleam
/// let assert Ok(server) = chat.start()
/// let server: process.Subject(Chat)
/// 
/// type Topic {
///   General
///   OffTopic
///   Cats
/// }
/// 
/// let assert Ok(registry) = group.start()
/// let registry: process.Subject(group.Message(Topic, Chat))
/// ```
/// 
/// By specifying the types we can document the kind of registry we are working with; in the example
/// above we can tell we're creating different "chat servers" under different topic groups. 
pub opaque type Message(group, msg) {
  GroupedSubjects(client: Subject(List(Subject(msg))), group: group)
  GroupedRegistrant(subject: Subject(msg), group: group)
  Demonitor(index: Index)
}

type Index {
  Index(pid: Pid, monitor: ProcessMonitor)
}

type Location(group, msg) {
  Location(group, Subject(msg))
}

type State(group, msg) {
  State(
    // A reference to the actor's subject.
    self: Registry(group, msg),
    // This tags multiple subjects under a group.
    groups: Dict(group, Set(Subject(msg))),
    // Index to help track monitored subjects and where to look on de-registration.
    subject_track: Dict(Pid, Set(Location(group, msg))),
    // There's no way of retrieving previous selector from current process, so we manually track it here.
    selector: Selector(Message(group, msg)),
  )
}

/// Starts the registry.
/// 
/// ## Example
/// 
/// ```gleam
/// > group.start()
/// Ok(registry)
/// ```
pub fn start() -> Result(Registry(group, msg), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: handle_init,
    init_timeout: 10,
    loop: handle_message,
  ))
}

/// Registers a `Subject` under a shared name. 
/// 
/// ## Example
/// 
/// ```gleam
/// > group.register(registry, process.new_subject(), "group-a")
/// Nil
/// ```
pub fn register(
  registry: Subject(Message(group, message)),
  subject: Subject(message),
  group: group,
) -> Nil {
  process.send(registry, GroupedRegistrant(subject, group))
}

/// Looks up `Subject`s under a named group.
/// 
/// ### Example
/// 
/// ```gleam
/// > group.find(registry, "group-a") 
/// [subject_1, subject_2, subject_3]
/// ```
pub fn members(registry, group) -> List(Subject(msg)) {
  process.call(registry, GroupedSubjects(_, group), 10)
}

/// Executes a callback for all `Subject`s under a named group.
/// 
/// ### Example
/// 
/// ```gleam
/// > group.dispatch(registry, "group-a", fn(subject) { 
/// >   process.send(subject, Message(data))
/// > })
/// Nil
/// ```
pub fn dispatch(
  registry: Subject(Message(group, message)),
  group: group,
  callback: fn(Subject(message)) -> x,
) -> Nil {
  let subjects = members(registry, group)
  use subject <- list.each(subjects)
  callback(subject)
}

fn handle_init() {
  let self = process.new_subject()

  let state =
    State(
      self: self,
      groups: dict.new(),
      subject_track: dict.new(),
      selector: process.new_selector()
        |> process.selecting(self, function.identity),
    )

  actor.Ready(state, state.selector)
}

fn handle_message(
  message: Message(group, message),
  state: State(group, message),
) {
  case message {
    GroupedSubjects(client, group) -> {
      let subjects = case dict.get(state.groups, group) {
        Ok(subjects) -> set.to_list(subjects)
        Error(Nil) -> []
      }

      process.send(client, subjects)
      actor.continue(state)
    }

    GroupedRegistrant(subject, group) -> {
      let pid = process.subject_owner(subject)
      let selection = monitor(state, pid)

      state
      |> into_group(group, subject)
      |> into_tracker(pid, Location(group, subject))
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

fn into_group(
  state: State(group, msg),
  group: group,
  subject: Subject(msg),
) -> State(group, msg) {
  let add_subject = fn(option) {
    case option {
      Some(subjects) -> set.insert(subjects, subject)
      None -> set.insert(set.new(), subject)
    }
  }

  State(..state, groups: dict.update(state.groups, group, add_subject))
}

fn into_tracker(
  state: State(group, msg),
  pid: Pid,
  location: Location(group, msg),
) -> State(group, msg) {
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
  state: State(group, msg),
  selection: Option(Selector(Message(group, msg))),
) -> State(group, msg) {
  case selection {
    Some(selector) -> State(..state, selector: selector)
    None -> state
  }
}

fn remove_from_group(state: State(group, msg), pid: Pid) -> State(group, msg) {
  let locations = case dict.get(state.subject_track, pid) {
    Ok(locations) -> {
      set.to_list(locations)
    }
    Error(Nil) -> {
      panic as "Impossible state, couldn't find a pid when removing from group."
    }
  }

  list.fold(locations, state, fn(state, location) {
    let Location(group, subject) = location

    case dict.get(state.groups, group) {
      Ok(subjects) -> {
        let subjects = set.delete(subjects, subject)
        let groups = dict.insert(state.groups, group, subjects)
        State(..state, groups: groups)
      }

      Error(Nil) -> {
        panic as "Impossible state, couldn't find the group when removing."
      }
    }
  })
}

fn remove_from_tracker(state: State(group, msg), pid: Pid) -> State(group, msg) {
  State(..state, subject_track: dict.delete(state.subject_track, pid))
}

fn monitor(
  state: State(group, msg),
  pid: Pid,
) -> Option(Selector(Message(group, msg))) {
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
  selector: Selector(Message(group, msg)),
  pid: Pid,
  monitor: ProcessMonitor,
) -> Selector(Message(group, msg)) {
  // Build the selector with an index to track down the location of subjects 
  // when a the process goes down.
  let index = Index(pid, monitor)
  let handle = fn(_: ProcessDown) { Demonitor(index) }
  process.selecting_process_down(selector, monitor, handle)
}
