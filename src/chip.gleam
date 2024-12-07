//// Chip is a local [subject](https://hexdocs.pm/gleam_erlang/gleam/erlang/process.html#Subject)
//// registry that can reference subjects individually or as part of a group. Will also
//// automatically delist dead processes.

// TODO: Rework docs and test docs.
// TODO: Document plan to research persistent term for the chip_registries table.
// TODO: Document plan for a dispatch function.

import gleam/dynamic
import gleam/erlang
import gleam/erlang/atom
import gleam/erlang/process.{type Pid, type Subject}
import gleam/function
import gleam/io
import gleam/otp/actor
import gleam/result.{try}
import gleam/string
import lamb.{Bag, Protected, Public, Set}
import lamb/query as q
import lamb/query/term as t

const registry_store = "chip_registries"

const group_store = "chip_groups"

/// An shorter alias for the registry's subject.
///
/// Sometimes, when building out your system it may be useful to state the Registry's types.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(registry) = chip.start(chip.Unnamed)
/// let registry: chip.Registry(Event, Topic)
/// ```
///
/// Which is equivalent to:
///
/// ```gleam
/// let assert Ok(registry) = chip.start()
/// let registry: process.Subject(chip.Message(Event, Topic))
/// ```
///
/// By specifying the types we can document the kind of registry we are working with.
pub type Registry(msg, group) =
  Subject(Message(msg, group))

/// An option passed to `chip.start` to make the registry available through a name.
pub type Named {
  Named(String)
  Unnamed
}

// API ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

/// Starts the registry.
///
/// ## Example
///
/// Normally, the registry may be started in an unnamed fashion. ///
/// ```gleam
/// > let assert Ok(registry) = chip.start(chip.Unnamed)
/// ```
///
/// You will need to provide a mechanism to carry around the registry's subject
/// through your system.
///
/// It is also possible to start a named registry.
///
/// ```gleam
/// > let _ = chip.start(chip.Named("sessions"))
///
/// You may retrieve now this registry's by using the `from` function.
pub fn start(named: Named) -> Result(Registry(msg, group), actor.StartError) {
  let init = fn() { init(named) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 100, loop: loop))
}

/// Retrieves a previously named registry.
///
/// ## Example
///
/// ```gleam
/// let _ = chip.start(chip.Named("sessions"))
/// let assert Ok(registry) = chip.from("sessions")
/// ```
///
/// This function can be useful when you don't have the registry's subject in scope.
/// Ideally, you would carry around the registry's subject down your pipeline and
/// always have it available but this can become hard to mantains if you don't
/// already provide a solid solution for your system.
///
/// Be mindful that using it means you lose type safety as the `from` function only
/// knows you return a registry but it doesn't know the message type or the group
/// type. It would not be a bad idea to wrap it under a typed function:
///
/// ```gleam
/// fn get_session(name: String) -> chip.Registry(Message, Groups) {
///   case chip.from("sessions") {
///     Ok(registry) -> registry
///     Error(Nil) -> panic as "session is not available"
///   }
/// }
/// ```
///
/// Even with the wrapper above, there's no guarantee of retrieving the right subject
/// as a typo on the name might return a registry with different message types
/// and groups.
pub fn from(name: String) -> Result(Registry(msg, group), Nil) {
  use table <- try(lamb.from_name(registry_store))

  let query =
    q.new()
    |> q.index(name)
    |> q.record(t.var(1))
    |> q.map(fn(_index, record) { record })

  case lamb.search(table, query) {
    [] -> Error(Nil)
    [registry] -> Ok(registry)
    [_, ..] ->
      panic as {
        "Unexpected error trying to retrieve registry "
        <> name
        <> " from ETS table: "
        <> registry_store
      }
  }
}

/// Registers a subject under a group.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(registry) = chip.start(chip.Unnamed)
///
/// chip.register(registry, GroupA, subject)
/// chip.register(registry, GroupB, subject)
/// chip.register(registry, GroupC, subject)
/// ```
///
/// A subject may be registered under multiple groups but it may only be
/// registered one time on each group.
///
/// It is possibel to register any subject at any point in time but keeping
/// it under the initialization step of your process may help to keep things
/// organized and tidy.
pub fn register(
  registry: Registry(msg, group),
  group: group,
  subject: Subject(msg),
) -> Nil {
  process.send(registry, Register(subject, group))
}

/// Retrieves all subjects from a given group. The order of retrieved
/// subjects is not guaranteed.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(registry) = chip.start(chip.Unnamed)
///
/// chip.register(registry, GroupA, subject)
/// chip.register(registry, GroupB, subject)
/// chip.register(registry, GroupA, subject)
///
/// let assert [_, _] = chip.members(registry, GroupA, 50)
/// let assert [_] = chip.members(registry, GroupB, 50)
/// ```
pub fn members(
  registry: Registry(msg, group),
  group: group,
  timeout: Int,
) -> List(Subject(msg)) {
  let group_store = process.call(registry, GroupStore(_), timeout)

  let query =
    q.new()
    |> q.index(#(group, t.any()))
    |> q.record(t.var(1))
    |> q.map(fn(_index, record) { record })

  lamb.search(group_store, query)
}

/// Stops the registry.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(registry) = chip.start(chip.Unnamed)
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
  GroupStore(Subject(lamb.Table(#(group, Pid), Subject(msg))))
  NoOperation(dynamic.Dynamic)
  Stop
}

type State(msg, group) {
  State(
    // This config dictates how many max tasks to launch on a dispatch.
    concurrency: Int,
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
  let self = process.new_subject()

  let table = initialize_named_registries_store()

  case named {
    Named(name) -> lamb.insert(table, name, self)
    Unnamed -> Nil
  }

  let concurrency = schedulers()
  let groups = initialize_groups_store()

  let state = State(concurrency: concurrency, groups: groups)

  let selector =
    process.new_selector()
    |> process.selecting(self, function.identity)
    |> process.selecting_anything(process_down)

  actor.Ready(state, selector)
}

fn loop(
  message: Message(msg, group),
  state: State(msg, group),
) -> actor.Next(Message(msg, group), State(msg, group)) {
  case message {
    GroupStore(client) -> {
      // priority is given through selective receive
      process.send(client, state.groups)

      state
      |> actor.continue()
    }

    Register(subject, group) -> {
      let pid = process.subject_owner(subject)
      // TODO: Lets avoid creating multiple independent monitors if pid is already registered
      let _monitor = process.monitor_process(pid)

      lamb.insert(state.groups, #(group, pid), subject)

      state
      |> actor.continue()
    }

    Demonitor(monitor, pid) -> {
      let Nil = demonitor(monitor)

      let query =
        q.new()
        |> q.index(#(t.any(), pid))

      lamb.remove(state.groups, where: query)

      state
      |> actor.continue()
    }

    NoOperation(message) -> {
      io.println(
        "chip: received an out of bound message from a non-selected process.\n"
        <> string.inspect(message),
      )

      state
      |> actor.continue()
    }

    Stop -> {
      actor.Stop(process.Normal)
    }
  }
}

fn initialize_named_registries_store() -> lamb.Table(
  String,
  Registry(msg, group),
) {
  case lamb.from_name(registry_store) {
    Ok(table) -> table
    Error(Nil) ->
      case lamb.create(registry_store, Public, Set, True) {
        Ok(table) -> table
        Error(_error) ->
          panic as {
            "Unexpected error trying to initialize chip's named registries ETS store"
          }
      }
  }
}

fn initialize_groups_store() -> lamb.Table(#(group, Pid), Subject(msg)) {
  case lamb.create(group_store, Protected, Bag, False) {
    Ok(groups) -> groups
    Error(_error) ->
      panic as { "Unexpected error trying to initialize chip's subject store" }
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
