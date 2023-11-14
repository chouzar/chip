////Chip is a gleam process registry that plays along gleam erlang/OTP `Subject` type. 
////
////It lets us group subjects of the same type so that we can later reference them all 
////as a group, or sub-group if we decide to name them. Will also automatically delist 
////dead processes.

import gleam/list
import gleam/map.{Map}
import gleam/set.{Set}
import gleam/result.{try}
import gleam/function.{identity}
import gleam/erlang/process.{Pid,
  ProcessDown, ProcessMonitor, Selector, Subject}
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

type State(name, message) {
  State(
    self: Subject(Action(name, message)),
    index: Map(Pid, ProcessMonitor),
    group: Set(Subject(message)),
    named: Map(name, Set(Subject(message))),
    selector: Selector(Action(name, message)),
  )
}

/// Starts the registry.
/// 
/// ## Example
/// 
/// ```gleam
/// > chip.start()
/// Ok(registry)
/// ```
pub fn start() -> Result(Subject(Action(name, message)), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: handle_init,
    init_timeout: 10,
    loop: handle_message,
  ))
}

/// Returns all registered `Subject`s.
/// 
/// ### Example
/// 
/// ```gleam
/// > chip.all(registry) 
/// [subject_a, subject_b, subject_c]
/// ```
pub fn all(registry: Subject(Action(name, message))) -> List(Subject(message)) {
  process.call(registry, All(_), 100)
}

/// Looks up named subgroup of `Subject`s.
/// 
/// ### Example
/// 
/// ```gleam
/// > chip.lookup(registry, "MySubjects") 
/// [subject_a, subject_c]
/// ```
pub fn lookup(
  registry: Subject(Action(name, message)),
  name: name,
) -> List(Subject(message)) {
  process.call(registry, Lookup(_, name), 100)
}

/// Manually registers a `Subject`. 
/// 
/// ## Example
/// 
/// ```gleam
/// > chip.register(registry, fn() { start_my_subject() })
/// Ok(registered_subject)
/// ```
pub fn register(
  registry: Subject(Action(name, message)),
  start: fn() -> Result(Subject(message), actor.StartError),
) -> Result(Subject(message), actor.StartError) {
  use subject <- try(start())
  process.send(registry, Register(subject))
  Ok(subject)
}

/// Manually registers a `Subject` under a named group. 
/// 
/// ## Example
/// 
/// ```gleam
/// > chip.register(registry, "MySubjects", fn() { start_my_subject() })
/// Ok(registered_subject)
/// ```
pub fn register_as(
  registry: Subject(Action(name, message)),
  name: name,
  start: fn() -> Result(Subject(message), actor.StartError),
) -> Result(Subject(message), actor.StartError) {
  use subject <- try(start())
  process.send(registry, RegisterAs(subject, name))
  Ok(subject)
}

/// Manually deregister a named group of `Subject`s.
/// 
/// ## Example
/// 
/// ```gleam
/// > chip.deregister(registry, "MySubjects")
/// Nil
/// ```
pub fn deregister(registry: Subject(Action(name, message)), name: name) -> Nil {
  process.send(registry, Deregister(name))
}

/// Stops the registry, all grouped `Subject`s will be gone.
/// 
/// ## Example
/// 
/// ```gleam
/// > chip.stop(registry)
/// Normal
/// ```
pub fn stop(registry: Subject(Action(name, message))) -> process.ExitReason {
  process.call(registry, Stop(_), 10)
}

fn handle_init() -> actor.InitResult(
  State(name, message),
  Action(name, message),
) {
  let subject = process.new_subject()

  let selector =
    process.new_selector()
    |> process.selecting(subject, identity)

  let state =
    State(
      self: subject,
      index: map.new(),
      group: set.new(),
      named: map.new(),
      selector: selector,
    )

  actor.Ready(state, selector)
}

fn handle_message(message: Action(name, message), state: State(name, message)) {
  case message {
    All(client) -> {
      let subjects = set.to_list(state.group)
      process.send(client, subjects)

      actor.continue(state)
    }

    Lookup(client, name) -> {
      let subjects =
        get_group(state.named, name)
        |> set.to_list()
      process.send(client, subjects)

      actor.continue(state)
    }

    Register(subject) -> {
      let state = insert(state, subject)

      actor.continue(state)
      |> actor.with_selector(state.selector)
    }

    RegisterAs(subject, name) -> {
      let state = insert_as(state, subject, name)

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

fn insert(
  state: State(name, message),
  subject: Subject(message),
) -> State(name, message) {
  let pid = process.subject_owner(subject)

  case map.get(state.index, pid) {
    Ok(monitor) -> {
      let group = set.insert(state.group, subject)
      let selector = receive_process_down(state.selector, monitor, subject)

      State(..state, group: group, selector: selector)
    }

    Error(Nil) -> {
      let monitor = process.monitor_process(pid)

      let index = map.insert(state.index, pid, monitor)
      let group = set.insert(state.group, subject)
      let selector = receive_process_down(state.selector, monitor, subject)

      State(..state, index: index, group: group, selector: selector)
    }
  }
}

fn insert_as(
  state: State(name, message),
  subject: Subject(message),
  name: name,
) -> State(name, message) {
  let subjects =
    state.named
    |> get_group(name)
    |> set.insert(subject)

  let named = map.insert(state.named, name, subjects)

  State(..state, named: named)
  |> insert(subject)
}

fn delete_named(state: State(name, message), name: name) -> State(name, message) {
  let other_named = map.delete(state.named, name)
  let other_subjects =
    map.fold(
      other_named,
      set.new(),
      fn(all_subjects, _name, subjects) { set.union(all_subjects, subjects) },
    )

  let subjects = get_group(state.named, name)

  let subjects_to_keep =
    set.intersection(subjects, other_subjects)
    |> set.to_list()

  let subjects_to_delete =
    set.drop(subjects, subjects_to_keep)
    |> set.to_list()

  let pids_to_delete =
    subjects_to_delete
    |> list.map(fn(subject) { process.subject_owner(subject) })

  let monitors =
    state.index
    |> map.take(pids_to_delete)
    |> map.values()

  list.each(monitors, process.demonitor_process)

  let index = map.drop(state.index, pids_to_delete)
  let group = set.drop(state.group, subjects_to_delete)
  let named = map.delete(state.named, name)
  State(..state, index: index, group: group, named: named)
}

fn demonitor_subject(
  state: State(name, message),
  subject: Subject(message),
) -> State(name, message) {
  let pid = process.subject_owner(subject)

  case map.get(state.index, pid) {
    Ok(monitor) -> {
      process.demonitor_process(monitor)

      let index = map.delete(state.index, pid)
      let group = set.delete(state.group, subject)
      let delete = fn(_name, subjects) { set.delete(subjects, subject) }
      let named = map.map_values(state.named, delete)

      State(..state, index: index, group: group, named: named)
    }

    Error(Nil) -> state
  }
}

fn get_group(
  named: Map(name, Set(Subject(message))),
  name: name,
) -> Set(Subject(message)) {
  case map.get(named, name) {
    Ok(subjects) -> subjects
    Error(Nil) -> set.new()
  }
}

fn rebuild_process_down_selectors(
  state: State(name, message),
) -> State(name, message) {
  let self = process.new_subject()

  let subjects = set.to_list(state.group)

  let selector =
    process.new_selector()
    |> process.selecting(self, identity)
    |> list.fold(
      subjects,
      _,
      fn(selector, subject) {
        let pid = process.subject_owner(subject)
        case map.get(state.index, pid) {
          Ok(monitor) -> receive_process_down(selector, monitor, subject)
          Error(Nil) -> selector
        }
      },
    )

  State(..state, self: self, selector: selector)
}

fn receive_process_down(
  selector: Selector(Action(name, message)),
  monitor: ProcessMonitor,
  subject: Subject(message),
) -> Selector(Action(name, message)) {
  let handle = fn(_process: ProcessDown) { Demonitor(subject) }
  process.selecting_process_down(selector, monitor, handle)
}
