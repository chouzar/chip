import gleam/list
import gleam/map.{Map}
import gleam/set.{Set}
import gleam/result
import gleam/erlang/process.{Pid,
  ProcessDown, ProcessMonitor, Selector, Subject}
import gleam/otp/actor.{StartError}

pub opaque type Action(name, message) {
  All(client: Subject(List(Subject(message))))
  Lookup(client: Subject(List(Subject(message))), name: name)
  Register(subject: Subject(message))
  RegisterAs(subject: Subject(message), name: name)
  Deregister(name: name)
  Unregister(subject: Subject(message), monitor: ProcessMonitor)
  UnregisterAs(subject: Subject(message), monitor: ProcessMonitor, name: name)
  Stop(client: Subject(Result(Nil, Nil)))
}

type State(message, name) {
  State(
    group: Map(Subject(message), ProcessMonitor),
    named: Map(name, Set(Subject(message))),
    selector: Selector(Action(name, message)),
  )
}

//type Record(message, name) {
//  // TODO: Do records if useful
//  Group(subject: Subject(message), monitor: ProcessMonitor)
//}

pub fn start() -> Result(Subject(Action(name, message)), StartError) {
  actor.start(
    State(map.new(), map.new(), process.new_selector()),
    handle_message,
  )
}

pub fn all(registry: Subject(Action(name, message))) -> List(Subject(message)) {
  process.call(registry, All(_), 100)
}

pub fn lookup(
  registry: Subject(Action(name, message)),
  name: name,
) -> List(Subject(message)) {
  process.call(registry, Lookup(_, name), 100)
}

pub fn register(
  registry: Subject(Action(name, message)),
  start: fn() -> Result(Subject(message), StartError),
) -> Result(Subject(message), StartError) {
  use subject <- result.try(start())
  process.send(registry, Register(subject))
  Ok(subject)
}

pub fn register_as(
  registry: Subject(Action(name, message)),
  name: name,
  start: fn() -> Result(Subject(message), StartError),
) -> Result(Subject(message), StartError) {
  use subject <- result.try(start())
  process.send(registry, RegisterAs(subject, name))
  Ok(subject)
}

pub fn deregister(registry: Subject(Action(name, message)), name: name) -> Nil {
  process.send(registry, Deregister(name))
}

pub fn stop(registry: Subject(Action(name, message))) -> Result(Nil, Nil) {
  process.call(registry, Stop(_), 10)
}

fn handle_message(message: Action(name, message), state: State(message, name)) {
  case message {
    All(client) -> {
      let subjects = map.keys(state.group)
      process.send(client, subjects)

      actor.continue(state)
    }

    Lookup(client, name) -> {
      let subjects =
        state
        |> get_named(name)
        |> set.to_list()
      process.send(client, subjects)

      actor.continue(state)
    }

    Register(subject) -> {
      let monitor = get_monitor(subject)
      let state = into_group(state, subject, monitor)

      actor.continue(state)
    }

    RegisterAs(subject, name) -> {
      let monitor = get_monitor(subject)
      let state = into_group(state, subject, monitor)
      let state = into_named(state, name, subject)

      actor.continue(state)
    }

    Deregister(name) -> {
      let state = delete_named(state, name)

      actor.continue(state)
    }

    Unregister(subject, monitor) -> {
      process.demonitor_process(monitor)
      let group = map.delete(state.group, subject)
      let state = State(..state, group: group)

      actor.continue(state)
    }

    UnregisterAs(subject, monitor, name) -> {
      process.demonitor_process(monitor)

      let group = map.delete(state.group, subject)
      let named = map.delete(state.named, name)
      let state = State(..state, group: group, named: named)

      actor.continue(state)
    }

    Stop(client) -> {
      process.send(client, Ok(Nil))

      actor.Stop(process.Normal)
    }
  }
}

fn get_named(state: State(message, name), name: name) -> Set(Subject(message)) {
  case map.get(state.named, name) {
    Ok(subjects) -> subjects
    Error(Nil) -> set.new()
  }
}

fn get_monitor(subject: Subject(message)) -> ProcessMonitor {
  subject
  |> process.subject_owner()
  |> process.monitor_process()
}

fn into_group(
  state: State(message, name),
  subject: Subject(message),
  monitor: ProcessMonitor,
) -> State(message, name) {
  let group = map.insert(state.group, subject, monitor)
  State(..state, group: group)
}

fn into_named(
  state: State(message, name),
  name: name,
  subject: Subject(message),
) -> State(message, name) {
  let subjects = get_named(state, name)
  let subjects = set.insert(subjects, subject)
  let named = map.insert(state.named, name, subjects)
  State(..state, named: named)
}

fn delete_named(state: State(message, name), name: name) -> State(message, name) {
  let other_named = map.delete(state.named, name)
  let other_subjects =
    map.fold(
      other_named,
      set.new(),
      fn(all_subjects, _name, subjects) { set.union(all_subjects, subjects) },
    )

  let subjects = get_named(state, name)

  let subjects_to_keep =
    set.intersection(subjects, other_subjects)
    |> set.to_list()

  let subjects_to_delete =
    set.drop(subjects, subjects_to_keep)
    |> set.to_list()

  let group = map.drop(state.group, subjects_to_delete)
  let named = map.delete(state.named, name)
  State(..state, group: group, named: named)
}
//fn select_process_down(
//  state: State(message, name),
//) -> Selector(Action(name, message)) {
//  let subjects_info = map.to_list(state.group)
//
//  list.fold(
//    subjects_info,
//    process.new_selector(),
//    fn(selector, subject_info) {
//      let #(subject, monitor) = subject_info
//      let handle_down = fn(_down: ProcessDown) { Unregister(subject, monitor) }
//      process.selecting_process_down(selector, monitor, handle_down)
//    },
//  )
//}
//
