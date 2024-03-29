import gleam/list
import gleam/set.{type Set}
import gleam/dict.{type Dict}
import gleam/option.{type Option, None, Some}
import gleam/erlang/process.{
  type Pid, type ProcessDown, type ProcessMonitor, type Selector, type Subject,
}
import gleam/otp/actor
import gleam/io

type Registry(name, group, message) =
  Subject(Message(name, group, message))

pub opaque type Message(name, group, msg) {
  Names(client: Subject(List(name)))
  NamedContent(client: Subject(Result(Subject(msg), Nil)), name: name)
  NamedRegistrant(subject: Subject(msg), name: name)
  Groups(client: Subject(List(group)))
  GroupedContent(client: Subject(List(Subject(msg))), group: group)
  GroupedRegistrant(subject: Subject(msg), group: group)
  Demonitor(index: Index)
}

type Index {
  Index(pid: Pid, monitor: ProcessMonitor)
}

type Record(msg, name, group) {
  Record(subject: Subject(msg), names: Set(name), groups: Set(group))
}

type SubjectLocation(name, group, msg) {
  NamedLocation(name)
  GroupedLocation(group, Subject(msg))
}

type State(name, group, msg) {
  State(
    // This is were all registered subjects are stored.
    // subjects: Dict(Reference, Subject(msg)),
    // This tags a subject under a unique name.
    names: Dict(name, Subject(msg)),
    // This tags multiple subjects under a group.
    groups: Dict(group, Set(Subject(msg))),
    // Index to help track monitored subjects and where to look on de-registration.
    subject_track: Dict(Pid, Set(SubjectLocation(name, group, msg))),
    // There's no way of retrieving previous selector from current process, so we manually track it here.
    selector: Selector(Message(name, group, msg)),
  )
}

pub fn start() -> Result(Registry(name, group, msg), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: handle_init,
    init_timeout: 10,
    loop: handle_message,
  ))
}

pub fn registered_names(registry) -> List(name) {
  process.call(registry, Names(_), 10)
}

pub fn registered_groups(registry) -> List(group) {
  process.call(registry, Groups(_), 10)
}

pub fn find(registry, name) -> Result(Subject(mssg), Nil) {
  process.call(registry, NamedContent(_, name), 10)
}

pub fn members(registry, group) -> List(Subject(msg)) {
  process.call(registry, GroupedContent(_, group), 10)
}

pub fn register(
  registry: Subject(Message(name, group, message)),
  subject: Subject(message),
  name: name,
) -> Nil {
  process.send(registry, NamedRegistrant(subject, name))
}

pub fn group(
  registry: Subject(Message(name, group, message)),
  subject: Subject(message),
  group: group,
) -> Nil {
  process.send(registry, GroupedRegistrant(subject, group))
}

fn handle_init() {
  let state =
    State(
      names: dict.new(),
      groups: dict.new(),
      subject_track: dict.new(),
      selector: process.new_selector(),
    )

  actor.Ready(state, state.selector)
}

fn handle_message(
  message: Message(name, group, message),
  state: State(name, group, message),
) {
  case message {
    Names(client) -> {
      let names = dict.keys(state.names)
      process.send(client, names)
      actor.continue(state)
    }

    NamedContent(client, name) -> {
      let result = dict.get(state.names, name)
      process.send(client, result)
      actor.continue(state)
    }

    NamedRegistrant(subject, name) -> {
      let pid = process.subject_owner(subject)
      let selection = monitor(state, pid)

      state
      |> into_names(name, subject)
      |> into_tracker(pid, NamedLocation(name))
      |> into_selector(selection)
      |> actor.Continue(selection)
    }

    Groups(client) -> {
      let groups = dict.keys(state.groups)
      process.send(client, groups)
      actor.continue(state)
    }

    GroupedContent(client, group) -> {
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
      |> into_tracker(pid, GroupedLocation(group, subject))
      |> into_selector(selection)
      |> actor.Continue(selection)
    }

    Demonitor(Index(pid, monitor)) -> {
      // Demonitor process
      process.demonitor_process(monitor)

      state
      |> remove_from_group(pid)
      |> remove_from_tracker(pid)
      |> actor.continue()
    }
  }
}

fn into_names(
  state: State(name, group, msg),
  name: name,
  subject: Subject(msg),
) -> State(name, group, msg) {
  State(..state, names: dict.insert(state.names, name, subject))
}

fn into_group(
  state: State(name, group, msg),
  group: group,
  subject: Subject(msg),
) -> State(name, group, msg) {
  let add_subject = fn(option) {
    case option {
      Some(subjects) -> set.insert(subjects, subject)
      None -> set.insert(set.new(), subject)
    }
  }

  State(..state, groups: dict.update(state.groups, group, add_subject))
}

fn into_tracker(
  state: State(name, group, msg),
  pid: Pid,
  location: SubjectLocation(name, group, msg),
) -> State(name, group, msg) {
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
  state: State(name, group, msg),
  selection: Option(Selector(Message(name, group, msg))),
) -> State(name, group, msg) {
  case selection {
    Some(selector) -> State(..state, selector: selector)
    None -> state
  }
}

fn remove_from_group(
  state: State(name, group, msg),
  pid: Pid,
) -> State(name, group, msg) {
  let locations = case dict.get(state.subject_track, pid) {
    Ok(locations) -> {
      set.to_list(locations)
    }
    Error(Nil) -> {
      io.print("pid was not in registry")
      io.debug(pid)
      panic as "pid was not in registry"
    }
  }

  list.fold(locations, state, fn(state, location) {
    case location {
      GroupedLocation(group, subject) ->
        case dict.get(state.groups, group) {
          Ok(subjects) -> {
            let subjects = set.delete(subjects, subject)
            let groups = dict.insert(state.groups, group, subjects)
            State(..state, groups: groups)
          }

          Error(Nil) -> {
            io.print("group was not in registry")
            io.debug(group)
            panic as "group was not in registry"
          }
        }

      NamedLocation(name) -> {
        let names = dict.delete(state.names, name)
        State(..state, names: names)
      }
    }
  })
}

fn remove_from_tracker(
  state: State(name, group, msg),
  pid: Pid,
) -> State(name, group, msg) {
  State(..state, subject_track: dict.delete(state.subject_track, pid))
}

fn monitor(
  state: State(name, group, msg),
  pid: Pid,
) -> Option(Selector(Message(name, group, msg))) {
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
  selector: Selector(Message(name, group, msg)),
  pid: Pid,
  monitor: ProcessMonitor,
) -> Selector(Message(name, group, msg)) {
  // Build the selector with an index to track down the location of subjects 
  // when a the process goes down.
  let index = Index(pid, monitor)
  let handle = fn(_: ProcessDown) { Demonitor(index) }
  process.selecting_process_down(selector, monitor, handle)
}
