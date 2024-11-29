//// Chip is a local [subject](https://hexdocs.pm/gleam_erlang/gleam/erlang/process.html#Subject)
//// registry that can reference subjects individually or as part of a group. Will also
//// automatically delist dead processes.

// TODO: Rework docs and test docs.
// TODO: Have a system for naming registry a global registry table with pids and names.
// TODO: Remove `new` API in favor of register_as and register_in
// TODO: Have a system for naming registry a global registry table with pids and names.
// TODO: Use persistent term? Single table, Multiple tables?
// TODO: Implement an all subjects function
// TODO: Implement a dispatch one function
// TODO: This whole section should be at init time.

import gleam/dynamic
import gleam/erlang
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/function
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/otp/task
import gleam/result.{try}
import gleam/string
import lamb.{Bag, Protected}
import lamb/query as q
import lamb/query/term as t

/// An shorter alias for the registry's Subject.
///
/// Sometimes, when building out your system it may be useful to state the Registry's types.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(registry) = chip.start()
/// let registry: chip.Registry(Event, Id, Topic)
/// ```
///
/// Which is equivalent to:
///
/// ```gleam
/// let assert Ok(registry) = chip.start()
/// let registry: Subject(chip.Message(Event, Id, Topic))
/// ```
///
/// By specifying the types we can document the kind of registry we are working with.
pub type Registry(msg, group) =
  Subject(Message(msg, group))

pub type Named {
  Named(String)
  Unnamed
}

// API ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

/// Starts the registry.
///
/// ## Example
///
/// ```gleam
/// > chip.start()
/// ```
pub fn start(named: Named) -> Result(Registry(msg, group), actor.StartError) {
  let init = fn() { init(named) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

// TODO: docs + warning on how to properly retrieve values from here.
// This is not type safe so will require maitenance from the programmer's end.
pub fn from(_name: String) -> Result(Registry(msg, group), Nil) {
  todo
}

/// Registers a "chip".
///
/// ## Example
///
/// ```gleam
/// let assert Ok(registry) = chip.start()
///
/// chip.new(subject)
/// |> chip.register(registry, _)
/// ```
///
/// The subject may be registered under a tag or group.
///
/// ```gleam
/// let assert Ok(registry) = chip.start()
///
/// chip.new(subject)
/// |> chip.tag("Francisco")
/// |> chip.group(Coffee)
/// |> chip.register(registry, _)
/// ```
///
/// You may register any subject at any point in time but usually keeping it under the initialization
/// step of your process (like an Actor's `init` callback) will keep things organized and tidy.
pub fn register(
  registry: Registry(msg, group),
  group: group,
  subject: Subject(msg),
) -> Nil {
  process.send(registry, Register(subject, group))
}

/// TODO: members docs.
pub fn members(
  registry: Registry(msg, group),
  group: group,
  timeout: Int,
) -> List(Subject(msg)) {
  process.call(registry, Members(_, group), timeout)
}

/// Applies a callback over all registered Subjects.
///
/// ## Example
///
/// ```gleam
/// chip.dispatch(registry, fn(subject) {
///   process.send(subject, message)
/// })
/// ```
pub fn dispatch(
  registry: Registry(msg, group),
  group: group,
  callback: fn(Subject(msg)) -> Nil,
) -> Nil {
  process.send(registry, Dispatch(callback, group))
}

/// Stops the registry.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(registry) = chip.start()
/// chip.stop(registry)
/// ```
pub fn stop(registry: Registry(msg, group)) -> Nil {
  process.send(registry, Stop)
}

// Server Code ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

type Monitor =
  erlang.Reference

/// Chip's internal message type.
pub opaque type Message(msg, group) {
  Register(Subject(msg), group)
  Demonitor(Monitor, Pid)
  Members(Subject(List(Subject(msg))), group)
  Dispatch(fn(Subject(msg)) -> Nil, group)
  NoOperation(dynamic.Dynamic)
  Stop
}

pub type Error {
  InvalidName(String)
  NameTaken(String)
}

type State(msg, group) {
  State(
    // This config dictates how many max tasks to launch on a dispatch.
    max_concurrency: Int,
    // Store for all grouped subjects, the indexed pid helps to identify already monitored processess.
    groups: lamb.Table(#(group, Pid), Subject(msg)),
  )
}

type ProcessDown {
  ProcessDown(monitor: Monitor, pid: Pid)
}

fn init(
  named: Named,
) -> actor.InitResult(State(msg, group), Message(msg, group)) {
  let initialize = fn() {
    let self = process.new_subject()
    use Nil <- try(name_registry(self, named))
    let groups = initialize_store()
    let concurrency = schedulers()
    let state = State(concurrency, groups)
    let selector =
      process.new_selector()
      |> process.selecting(self, function.identity)
      |> process.selecting_anything(process_down)

    Ok(actor.Ready(state, selector))
  }

  initialize()
  |> result.map_error(translate_init_error)
  |> result.map_error(actor.Failed)
  |> result.unwrap_both()
}

fn loop(
  message: Message(msg, group),
  state: State(msg, group),
) -> actor.Next(Message(msg, group), State(msg, group)) {
  case message {
    Register(subject, group) -> {
      let pid = process.subject_owner(subject)
      // TODO: Lets avoid creating multiple independent monitors if pid is already registered
      let _monitor = process.monitor_process(pid)

      lamb.insert(state.groups, #(group, pid), subject)

      actor.Continue(state, option.None)
    }

    Demonitor(monitor, pid) -> {
      let Nil = demonitor(monitor)

      let query =
        q.new()
        |> q.index(#(t.any(), pid))

      lamb.remove(state.groups, where: query)

      actor.Continue(state, option.None)
    }

    Members(client, group) -> {
      let query =
        q.new()
        |> q.index(#(group, t.any()))
        |> q.record(t.var(1))
        |> q.map(fn(_index, record) { record })

      let records: List(Subject(msg)) = lamb.search(state.groups, query)
      process.send(client, records)
      actor.Continue(state, option.None)
    }

    Dispatch(callback, group) -> {
      let query =
        q.new()
        |> q.index(#(group, t.any()))
        |> q.record(t.var(1))
        |> q.map(fn(_index, record) { record })

      start_dispatch(state.groups, query, state.max_concurrency, callback)

      actor.Continue(state, option.None)
    }

    NoOperation(message) -> {
      io.println(
        "chip: received an out of bound message from a non-selected process.\n"
        <> string.inspect(message),
      )

      actor.Continue(state, option.None)
    }

    Stop -> {
      actor.Stop(process.Normal)
    }
  }
}

fn initialize_store() -> lamb.Table(#(group, Pid), Subject(msg)) {
  case lamb.create("chip_store_groups", Protected, Bag, False) {
    Ok(groups) -> groups
    Error(_error) ->
      panic as { "Unexpected error trying to initialize chip's ETS store" }
  }
}

fn name_registry(
  registry: Registry(msg, group),
  named: Named,
) -> Result(Nil, Error) {
  let is_valid_name = fn(name: Atom) {
    case name == atom.create_from_string("undefined") {
      True -> Error(InvalidName("undefined"))
      False -> Ok(Nil)
    }
  }

  let is_name_taken = fn(name: Atom) {
    case process.named(name) {
      Ok(_pid) -> Error(NameTaken(atom.to_string(name)))
      Error(Nil) -> Ok(Nil)
    }
  }

  let register = fn(pid, name) {
    case process.register(pid, name) {
      Ok(Nil) -> Nil
      Error(Nil) ->
        panic as {
          "Unexpected error trying to name registry as: "
          <> atom.to_string(name)
        }
    }
  }

  case named {
    Named(name) -> {
      let pid = process.subject_owner(registry)
      let name = atom.create_from_string(name)
      use Nil <- try(is_valid_name(name))
      use Nil <- try(is_name_taken(name))
      register(pid, name)

      Ok(Nil)
    }

    Unnamed -> {
      Ok(Nil)
    }
  }
}

fn translate_init_error(error) {
  case error {
    InvalidName(name) -> "Registry cannot be named " <> name

    NameTaken(name) -> "Name " <> name <> " is already taken by another process"
  }
}

// TODO: Change back to selecting_process_down
// The process.selecting_process_down function accumulates selections
// and would rather avoid this memory hit.
fn process_down(message) {
  case decode_down_message(message) {
    Ok(ProcessDown(monitor, pid)) -> {
      Demonitor(monitor, pid)
    }

    Error(Nil) -> {
      NoOperation(message)
    }
  }
}

fn start_dispatch(
  table: lamb.Table(index, record),
  query: q.Query(i, r, b),
  concurrency: Int,
  callback: fn(Subject(msg)) -> Nil,
) -> Nil {
  process.start(
    running: fn() {
      table
      |> lamb.batch(by: concurrency, where: query)
      |> handle_dispatch_results(callback)
    },
    linked: False,
  )

  Nil
}

fn continue_dispatch(step: lamb.Step, task: fn(Subject(msg)) -> Nil) -> Nil {
  lamb.continue(step)
  |> handle_dispatch_results(task)
}

fn handle_dispatch_results(
  partial: lamb.Partial(Subject(msg)),
  callback: fn(Subject(msg)) -> Nil,
) {
  case partial {
    lamb.Records(records, step) -> {
      records
      |> run_batch(callback)

      continue_dispatch(step, callback)
    }

    lamb.End(records) -> {
      records
      |> run_batch(callback)
    }
  }
}

fn run_batch(
  subjects: List(Subject(msg)),
  callback: fn(Subject(msg)) -> Nil,
) -> Nil {
  subjects
  |> list.map(fn(subject) { task.async(fn() { callback(subject) }) })
  |> list.each(fn(task) { task.await(task, 5000) })
}

@external(erlang, "chip_erlang_ffi", "decode_down_message")
fn decode_down_message(message: dynamic.Dynamic) -> Result(ProcessDown, Nil)

fn schedulers() -> Int {
  ffi_system_info(atom.create_from_string("schedulers"))
}

type Option =
  atom.Atom

@external(erlang, "erlang", "system_info")
fn ffi_system_info(option: Option) -> Int

fn demonitor(reference: Monitor) -> Nil {
  let _ = ffi_demonitor(reference, [atom.create_from_string("flush")])
  Nil
}

@external(erlang, "erlang", "demonitor")
fn ffi_demonitor(reference: Monitor, options: List(Option)) -> Bool
