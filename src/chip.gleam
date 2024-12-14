//// Chip is a local [subject](https://hexdocs.pm/gleam_erlang/gleam/erlang/process.html#Subject)
//// registry that can store Gleam process subjects as part of a group. Will also
//// automatically delist dead processes.

import gleam/dynamic
import gleam/erlang
import gleam/erlang/atom
import gleam/erlang/process.{type Pid, type Subject}
import gleam/function
import gleam/otp/actor
import gleam/result.{try}
import lamb.{Bag, Private, Protected, Public, Set}
import lamb/query as q
import lamb/query/term as t

const registry_store = "chip_registries"

const monitor_store = "chip_monitors"

const group_store = "chip_groups"

/// A shorter alias for the registry's subject.
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
/// The registry may be started in an unnamed fashion.
///
/// ```gleam
/// > let assert Ok(registry) = chip.start(chip.Unnamed)
/// ```
///
/// As a convenience, it is also possible to start a named registry which can be
/// retrieved later by using [from](#from).
///
/// ```gleam
/// > let _ = chip.start(chip.Named("sessions"))
/// ```
pub fn start(named: Named) -> Result(Registry(msg, group), actor.StartError) {
  let init = fn() { init(named) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 100, loop: loop))
}

/// Retrieves a previously named registry.
///
/// ## Example
///
/// This function can be useful when there is no registry subject in scope.
///
/// ```gleam
/// let _ = chip.start(chip.Named("sessions"))
/// let assert Ok(registry) = chip.from("sessions")
/// ```
///
/// Be mindful that using `from` means you lose type safety as the original `group` and
/// subject `message` will be not inferred from it. To circunvent this it is possible
/// to manually specify the type signature.
///
/// ```gleam
/// let assert Ok(registry) = chip.from("sessions")
///
/// // specify through a typed variable
/// let registry: chip.Registry(Message, Groups)
///
/// // specify through a helper function
/// fn get_session(name: String) -> chip.Registry(Message, Groups) {
///   case chip.from("sessions") {
///     Ok(registry) -> registry
///     Error(Nil) -> panic as "session is not available"
///   }
/// }
/// ```
pub fn from(name: String) -> Result(Registry(msg, group), Nil) {
  use table <- try(lamb.from_name(registry_store))

  case lamb.lookup(table, name) {
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
pub fn register(
  registry: Registry(msg, group),
  group: group,
  subject: Subject(msg),
) -> Nil {
  process.send(registry, Register(subject, group))
}

/// Retrieves all subjects from a given group, order of retrieved
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
  let group_store = process.call(registry, GroupStore2(_), timeout)

  lamb.lookup(group_store, group)
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
  Deregister(Monitor, Pid)
  GroupStore2(Subject(lamb.Table(group, Subject(msg))))
  NoOperation(dynamic.Dynamic)
  Stop
}

type State(msg, group) {
  State(
    // This config dictates how many max tasks to launch on a dispatch.
    concurrency: Int,
    // Store to track monitored pids, to avoid duplicate monitored pids.
    monitors: lamb.Table(Pid, Nil),
    // Store for all grouped subjects, the indexed pid helps to identify already monitored processess.
    groups: lamb.Table(group, Subject(msg)),
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
  let monitors = initialize_monitors_store()
  let groups = initialize_groups_store()

  let state =
    State(concurrency: concurrency, monitors: monitors, groups: groups)

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
    GroupStore2(client) -> {
      // priority is given through selective receive
      process.send(client, state.groups)

      state
      |> actor.continue()
    }

    Register(subject, group) -> {
      let pid = process.subject_owner(subject)

      let Nil = monitor(state.monitors, pid)
      lamb.insert(state.monitors, pid, Nil)
      lamb.insert(state.groups, group, subject)

      state
      |> actor.continue()
    }

    Deregister(monitor, pid) -> {
      let Nil = demonitor(monitor)

      lamb.remove(state.monitors, where: q.new() |> q.index(pid))
      lamb.remove(
        state.groups,
        where: q.new()
          |> q.record(#(t.tag("subject"), pid, t.any())),
      )

      state
      |> actor.continue()
    }

    NoOperation(_message) -> {
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
          panic as { "Unexpected error trying to initialize chip's ETS store" }
      }
  }
}

fn initialize_monitors_store() -> lamb.Table(Pid, Nil) {
  case lamb.create(monitor_store, Private, Set, False) {
    Ok(table) -> table
    Error(_error) ->
      panic as { "Unexpected error trying to initialize chip's monitor store" }
  }
}

fn initialize_groups_store() -> lamb.Table(group, Subject(msg)) {
  case lamb.create(group_store, Protected, Bag, False) {
    Ok(groups) -> groups
    Error(_error) ->
      panic as { "Unexpected error trying to initialize chip's subject store" }
  }
}

fn process_down(message) -> Message(msg, group) {
  // Could have used process.selecting_process_down but wanted to avoid
  // accumulating a big quantity selections at the actor level.
  case decode_down_message(message) {
    Ok(ProcessDown(monitor, pid)) -> {
      Deregister(monitor, pid)
    }

    Error(Nil) -> {
      NoOperation(message)
    }
  }
}

fn monitor(monitors: lamb.Table(Pid, Nil), pid: Pid) -> Nil {
  // TODO: Test this functionality for race conditions.
  case lamb.any(monitors, pid) {
    True -> Nil
    False -> {
      let _monitor = process.monitor_process(pid)
      Nil
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
