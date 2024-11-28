//// Chip is a local [subject](https://hexdocs.pm/gleam_erlang/gleam/erlang/process.html#Subject)
//// registry that can reference subjects individually or as part of a group. Will also
//// automatically delist dead processes.

import gleam/dynamic
import gleam/erlang
import gleam/erlang/atom
import gleam/erlang/process.{type Pid, type Subject}
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/otp/task
import gleam/result.{try}
import gleam/string
import lamb
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
pub type Registry(msg, tag, group) =
  Subject(Message(msg, tag, group))

// API ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

/// Starts the registry.
///
/// ## Example
///
/// ```gleam
/// > chip.start()
/// ```
pub fn start() -> Result(Registry(msg, tag, group), actor.StartError) {
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

// TODO: Have a system for naming registry a global registry table with pids and names.
// TODO: Remove `new` API in favor of register_as and register_in
// TODO: Have a system for naming registry a global registry table with pids and names.
// TODO: Use persistent term? Single table, Multiple tables?
// TODO: Implement an all subjects function
// TODO: Implement a dispatch one function
pub fn name(
  registry: Registry(msg, tag, group),
  name: String,
) -> Result(Registry(msg, tag, group), actor.StartError) {
  let pid = process.subject_owner(registry)
  let name = atom.create_from_string(name)

  case process.register(pid, name) {
    Ok(Nil) -> Ok(registry)
    Error(Nil) -> {
      // The process for the pid no longer exists.
      // The name has already been registered.
      // The process already has a name.
      // The name is the atom undefined, which is reserved by Erlang.

      let reason = process.Abnormal("Process is no longer alive.")
      Error(actor.InitFailed(reason))
    }
  }
}

pub fn from(_name: String) -> Result(Registry(msg, tag, group), Nil) {
  todo
}

@external(erlang, "observer", "start")
pub fn observer() -> Int

/// Creates a new "chip" that can be tagged, grouped and registered.
///
/// ## Example
///
/// ```gleam
/// chip.new(subject)
/// ```
pub fn new(subject: Subject(msg)) -> Chip(msg, tag, group) {
  Chip(subject, option.None, option.None)
}

/// Adds a unique tag to a "chip", it will overwrite any previous subject under the same tag.
///
/// ## Example
///
/// ```gleam
/// chip.new(subject)
/// |> chip.tag("Luis")
/// ```
pub fn tag(registrant: Chip(msg, tag, group), tag: tag) -> Chip(msg, tag, group) {
  Chip(..registrant, tag: option.Some(tag))
}

/// Adds the "chip" under a group.
///
/// ## Example
///
/// ```gleam
/// chip.new(subject)
/// |> chip.group(General)
/// ```
pub fn group(
  registrant: Chip(msg, tag, group),
  group: group,
) -> Chip(msg, tag, group) {
  Chip(..registrant, group: option.Some(group))
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
  registry: Registry(msg, tag, group),
  registrant: Chip(msg, tag, group),
) -> Nil {
  process.send(registry, Register(registrant))
}

/// Retrieves a tagged subject.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(subject) = chip.find(registry, "Luis")
/// ```
pub fn find(
  registry: Registry(msg, tag, group),
  tag,
) -> Result(Subject(msg), Nil) {
  let table = process.call(registry, Find(_), 500)

  let select_record = fn(_index, _record) { t.var(1) }

  let query =
    q.new()
    |> q.index(tag)
    |> q.record(#(t.any(), t.var(1)))
    |> q.map(select_record)
  case lamb.search(table, query) {
    [] -> Error(Nil)
    [subject] -> Ok(subject)
    [_, ..] -> panic as "impossible lookup on tagged table."
  }
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
  registry: Registry(msg, tag, group),
  callback: fn(Subject(msg)) -> Nil,
) -> Nil {
  process.send(registry, Dispatch(callback))
}

/// Applies a callback over a group.
///
/// ## Example
///
/// ```gleam
/// chip.dispatch_group(registry, Pets, fn(subject) {
///   process.send(subject, message)
/// })
/// ```
pub fn dispatch_group(
  registry: Registry(msg, tag, group),
  group: group,
  callback: fn(Subject(msg)) -> Nil,
) -> Nil {
  process.send(registry, DispatchGroup(callback, group))
}

/// Stops the registry.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(registry) = chip.start()
/// chip.stop(registry)
/// ```
pub fn stop(registry: Registry(msg, tag, group)) -> Nil {
  process.send(registry, Stop)
}

// Server Code ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

type Monitor =
  erlang.Reference

/// Chip's internal message type.
pub opaque type Message(msg, tag, group) {
  Register(Chip(msg, tag, group))
  Demonitor(Monitor, Pid)
  Find(Subject(lamb.Table(tag, #(Pid, Subject(msg)))))
  Dispatch(fn(Subject(msg)) -> Nil)
  DispatchGroup(fn(Subject(msg)) -> Nil, group)
  NoOperation(dynamic.Dynamic)
  Stop
}

/// A "chip" used for registration. Check the [new](#new) function.
pub opaque type Chip(msg, tag, group) {
  Chip(
    subject: Subject(msg),
    tag: option.Option(tag),
    group: option.Option(group),
  )
}

type State(msg, tag, group) {
  State(
    // This config dictates how many max tasks to launch on a dispatch.
    max_concurrency: Int,
    // TODO: If already storing the subject why do we need the pid?
    // Store for all registered subjects.
    registered: lamb.Table(Pid, Subject(msg)),
    // Store for all tagged subjects.
    tagged: lamb.Table(tag, #(Pid, Subject(msg))),
    // Store for all grouped subjects.
    grouped: lamb.Table(group, #(Pid, Subject(msg))),
  )
}

type ProcessDown {
  ProcessDown(monitor: Monitor, pid: Pid)
}

fn init() -> actor.InitResult(State(msg, tag, group), Message(msg, tag, group)) {
  // The process.selecting_process_down function accumulated selections until it made
  // the actor non-responsive.
  let process_down = fn(message) {
    case decode_down_message(message) {
      Ok(ProcessDown(monitor, pid)) -> {
        Demonitor(monitor, pid)
      }

      Error(Nil) -> {
        NoOperation(message)
      }
    }
  }

  let assert Ok(registered) =
    lamb.create(
      name: "chip_registry",
      access: lamb.Protected,
      kind: lamb.Set,
      registered: False,
    )

  let assert Ok(tagged) =
    lamb.create(
      name: "chip_registry_tagged",
      access: lamb.Protected,
      kind: lamb.Set,
      registered: False,
    )

  let assert Ok(grouped) =
    lamb.create(
      name: "chip_registry_group",
      access: lamb.Protected,
      kind: lamb.Bag,
      registered: False,
    )

  actor.Ready(
    State(
      max_concurrency: schedulers(),
      registered: registered,
      tagged: tagged,
      grouped: grouped,
    ),
    process.new_selector()
      |> process.selecting_anything(process_down),
  )
}

fn loop(
  message: Message(msg, tag, group),
  state: State(msg, tag, group),
) -> actor.Next(Message(msg, tag, group), State(msg, tag, group)) {
  case message {
    Register(registrant) -> {
      let Nil = insert(state, registrant)
      actor.Continue(state, option.None)
    }

    Demonitor(monitor, pid) -> {
      let Nil = delete(state, monitor, pid)
      actor.Continue(state, option.None)
    }

    Find(client) -> {
      process.send(client, state.tagged)
      actor.Continue(state, option.None)
    }

    Dispatch(callback) -> {
      let query =
        q.new()
        |> q.record(t.var(1))
        |> q.map(fn(_index, _record) { t.var(1) })

      start_dispatch(state.registered, query, state.max_concurrency, callback)

      actor.Continue(state, option.None)
    }

    DispatchGroup(callback, group) -> {
      let query =
        q.new()
        |> q.index(group)
        |> q.record(#(t.any(), t.var(1)))
        |> q.map(fn(_index, _record) { t.var(1) })

      start_dispatch(state.grouped, query, state.max_concurrency, callback)

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

fn insert(
  state: State(msg, tag, group),
  registrant: Chip(msg, tag, group),
) -> Nil {
  let pid = process.subject_owner(registrant.subject)
  let _monitor = process.monitor_process(pid)

  lamb.insert(state.registered, pid, registrant.subject)

  option.map(registrant.tag, fn(tag) {
    lamb.insert(state.tagged, tag, #(pid, registrant.subject))
  })

  option.map(registrant.group, fn(group) {
    lamb.insert(state.grouped, group, #(pid, registrant.subject))
  })

  Nil
}

fn delete(state: State(msg, tag, group), monitor: Monitor, pid: Pid) -> Nil {
  let Nil = demonitor(monitor)

  lamb.remove(state.registered, where: q.new() |> q.index(pid))
  lamb.remove(state.tagged, where: q.new() |> q.record(#(pid, t.any())))
  lamb.remove(state.grouped, where: q.new() |> q.record(#(pid, t.any())))
  Nil
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
