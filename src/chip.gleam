import gleam/list
import gleam/map.{Map}
import gleam/set.{Set}
import gleam/result.{try}
import gleam/erlang/process.{ProcessDown, ProcessMonitor, Selector, Subject}
import gleam/otp/actor

pub opaque type Action(name, message) {
  All(client: Subject(List(Subject(message))))
  Lookup(client: Subject(List(Subject(message))), name: name)
  Register(subject: Subject(message))
  RegisterAs(subject: Subject(message), name: name)
  Deregister(name: name)
  Demonitor(subject: Subject(message))
  RebuildSelector
  Stop(client: Subject(process.ExitReason))
}

type State(message, name) {
  State(
    self: Subject(Action(name, message)),
    group: Map(Subject(message), ProcessMonitor),
    named: Map(name, Set(Subject(message))),
    selector: Selector(Action(name, message)),
  )
}

pub fn start() -> Result(Subject(Action(name, message)), actor.StartError) {
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
  start: fn() -> Result(Subject(message), actor.StartError),
) -> Result(Subject(message), actor.StartError) {
  use subject <- try(start())
  process.send(registry, Register(subject))
  Ok(subject)
}

pub fn register_as(
  registry: Subject(Action(name, message)),
  name: name,
  start: fn() -> Result(Subject(message), actor.StartError),
) -> Result(Subject(message), actor.StartError) {
  use subject <- try(start())
  process.send(registry, RegisterAs(subject, name))
  Ok(subject)
}

pub fn deregister(registry: Subject(Action(name, message)), name: name) -> Nil {
  process.send(registry, Deregister(name))
}

pub fn stop(registry: Subject(Action(name, message))) -> process.ExitReason {
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
        state.named
        |> get_name(name)
        |> set.to_list()

      process.send(client, subjects)

      actor.continue(state)
    }

    Register(subject) -> {
      let monitor =
        subject
        |> process.subject_owner()
        |> process.monitor_process()

      let state = insert(state, subject, monitor)

      actor.continue(state)
      |> actor.with_selector(state.selector)
    }

    RegisterAs(subject, name) -> {
      let monitor =
        subject
        |> process.subject_owner()
        |> process.monitor_process()

      let state = insert_as(state, subject, monitor, name)

      actor.continue(state)
      |> actor.with_selector(state.selector)
    }

    Deregister(name) -> {
      let state = delete_named(state, name)
      process.send(state.self, RebuildSelector)

      actor.continue(state)
    }

    Demonitor(subject) -> {
      let state = demonitor_subject(state, subject)
      process.send(state.self, RebuildSelector)

      actor.continue(state)
    }

    RebuildSelector -> {
      let state = rebuild_process_down_selectors(state)

      actor.continue(state)
      |> actor.with_selector(state.selector)
    }

    Stop(client) -> {
      process.send(client, process.Normal)

      actor.Stop(process.Normal)
    }
  }
}

fn rebuild_process_down_selectors(
  state: State(message, name),
) -> State(message, name) {
  let subjects_info = map.to_list(state.group)

  let selector =
    list.fold(
      subjects_info,
      process.new_selector(),
      fn(selector, subject_info) {
        let #(subject, monitor) = subject_info
        capture_process_down(selector, monitor, subject)
      },
    )

  State(..state, selector: selector)
}

fn insert(
  state: State(message, name),
  subject: Subject(message),
  monitor: ProcessMonitor,
) -> State(message, name) {
  let group = map.insert(state.group, subject, monitor)
  let selector = capture_process_down(state.selector, monitor, subject)

  State(..state, group: group, selector: selector)
}

fn insert_as(
  state: State(message, name),
  subject: Subject(message),
  monitor: ProcessMonitor,
  name: name,
) -> State(message, name) {
  let subjects =
    state.named
    |> get_name(name)
    |> set.insert(subject)

  let named = map.insert(state.named, name, subjects)

  State(..state, named: named)
  |> insert(subject, monitor)
}

fn delete_named(state: State(message, name), name: name) -> State(message, name) {
  let other_named = map.delete(state.named, name)
  let other_subjects =
    map.fold(
      other_named,
      set.new(),
      fn(all_subjects, _name, subjects) { set.union(all_subjects, subjects) },
    )

  let subjects = get_name(state.named, name)

  let subjects_to_keep =
    set.intersection(subjects, other_subjects)
    |> set.to_list()

  let subjects_to_delete =
    set.drop(subjects, subjects_to_keep)
    |> set.to_list()

  let monitors =
    state.group
    |> map.take(subjects_to_delete)
    |> map.values()

  list.each(monitors, process.demonitor_process)

  let group = map.drop(state.group, subjects_to_delete)

  let named = map.delete(state.named, name)
  State(..state, group: group, named: named)
}

fn demonitor_subject(
  state: State(message, name),
  subject: Subject(message),
) -> State(message, name) {
  case map.get(state.group, subject) {
    Ok(monitor) -> {
      process.demonitor_process(monitor)

      let group = map.delete(state.group, subject)

      let named =
        map.map_values(
          state.named,
          fn(_name, subjects) { set.delete(subjects, subject) },
        )

      let state = State(..state, group: group, named: named)

      state
    }

    Error(Nil) -> state
  }
}

fn get_name(
  named: Map(name, Set(Subject(message))),
  name: name,
) -> Set(Subject(message)) {
  case map.get(named, name) {
    Ok(subjects) -> subjects
    Error(Nil) -> set.new()
  }
}

fn capture_process_down(
  selector: Selector(Action(name, message)),
  monitor: ProcessMonitor,
  subject: Subject(message),
) -> Selector(Action(name, message)) {
  let handle = fn(_process: ProcessDown) { Demonitor(subject) }
  process.selecting_process_down(selector, monitor, handle)
}
