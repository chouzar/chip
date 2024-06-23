//// Chip is a local process registry that plays along with Gleam's `Subject` type for referencing
//// erlang processes. It can hold to a set of subjects to later reference them and dispatch 
//// messages individually or as a group. Will also automatically delist dead processes.

import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/set.{type Set}

pub fn main() {
  todo
}

// API ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

/// Starts the registry.
/// 
/// ## Example
/// 
/// ```gleam
/// > chip.start()
/// ```
pub fn start() -> Result(Registry(msg, tag, group), actor.StartError) {
  // TODO: Send a messsage back to the client ???
  // TODO: Should be at, top of supervision tree
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

/// Creates a new registrant value. 
/// 
/// ## Example
/// 
/// ```gleam
/// chip.new(subject)
/// ```
pub fn new(subject: process.Subject(msg)) -> Registrant(msg, tag, group) {
  Registrant(subject, option.None, option.None)
}

/// Adds a unique tag to a registrant, it will overwrite any previous subject under the same tag.
/// 
/// ## Example
/// 
/// ```gleam
/// chip.new(subject)
/// |> chip.tag("Luis") 
/// ```
pub fn tag(
  registrant: Registrant(msg, tag, group),
  tag: tag,
) -> Registrant(msg, tag, group) {
  Registrant(..registrant, tag: option.Some(tag))
}

/// Adds the registrant under a group. 
/// 
/// ## Example
/// 
/// ```gleam
/// chip.new(subject)
/// |> chip.group(General) 
/// ```
pub fn group(
  registrant: Registrant(msg, tag, group),
  group: group,
) -> Registrant(msg, tag, group) {
  Registrant(..registrant, group: option.Some(group))
}

/// Registers a `Registrant`. 
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
/// `Registrant` may be registered under a tag or group.
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
  registrant: Registrant(msg, tag, group),
) -> Nil {
  process.send(registry, Register(registrant))
}

// Retrieves all tags on the registry.
/// 
/// ## Example
/// 
/// ```gleam
/// let assert Ok(registry) = chip.start()
/// 
/// let assert [_tag, ..tags] = chip.tags(registry)
/// ```
pub fn tags(registry: Registry(msg, tag, group)) -> List(tag) {
  // TODO: May be obtained from ETS directly
  todo
}

/// Retrieves all groups on the registry.
/// 
/// ## Example
/// 
/// ```gleam
/// let assert Ok(registry) = chip.start()
/// 
/// let assert [_group, ..groups] = chip.groups(registry)
/// ```
pub fn groups(registry: Registry(msg, tag, group)) -> List(group) {
  // TODO: May be obtained from ETS directly
  todo
}

/// TODO: Should this function be a dispatch?
/// Retrieves all registered subjects.
/// 
/// ## Example
/// 
/// ```gleam
/// let assert [subject, ..subjects] = chip.groups(registry)
/// ```
pub fn registered(
  registry: Registry(msg, tag, group),
) -> List(process.Subject(msg)) {
  // TODO: May be obtained from ETS directly
  todo
}

/// TODO: Should this function be renamed to lookup?
/// Retrieves a tagged subject.
/// 
/// ## Example
/// 
/// ```gleam
/// let assert Ok(subject) = chip.tagged(registry, "Luis")
/// ```
pub fn tagged(
  registry: Registry(msg, tag, group),
  tag,
) -> Result(process.Subject(msg), Nil) {
  // TODO: May be obtained from ETS directly
  todo
}

/// TODO: Should this function be a dispatch_group?
/// Retrieves subjects under a group.
/// 
/// ## Example
/// 
/// ```gleam
/// let assert [subject, ..subjects] = chip.grouped(registry, Coffee)
/// ```
pub fn grouped(
  registry: Registry(msg, tag, group),
  group,
) -> List(process.Subject(msg)) {
  // TODO: May be obtained from ETS directly
  todo
}

/// A helper function that will apply a callback over a list of Subjects.
/// 
/// ## Example
/// 
/// ```gleam
/// group.dispatch(subjects, fn(subject) { 
///   process.send(subject, Message(data))
/// })
/// ```
pub fn dispatch(
  subjects: List(process.Subject(msg)),
  callback: fn(process.Subject(msg)) -> x,
) -> Nil {
  todo
}

// Server Code ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

type Registry(msg, tag, group) =
  process.Subject(Message(msg, tag, group))

pub opaque type Message(msg, tag, group) {
  Register(Registrant(msg, tag, group))
  // TODO: If demonitoring executes 1 time only the PID here is not necessary.
  Demonitor(process.ProcessMonitor, process.Pid, Registrant(msg, tag, group))
}

pub opaque type Registrant(msg, tag, group) {
  Registrant(
    subject: process.Subject(msg),
    tag: option.Option(tag),
    group: option.Option(group),
  )
}

type State(msg, tag, group) {
  State(
    // This keeps track of registered subjects and where to look for them on de-registration.
    // TODO: If demonitoring executes 1 time only this is not necessary.
    registration: Dict(process.Pid, Set(Registrant(msg, tag, group))),
    // Store for all registered subjects.
    registered: Set(process.Subject(msg)),
    // Store for all tagged subjects. 
    tagged: Dict(tag, process.Subject(msg)),
    // Store for all grouped subjects.
    grouped: Dict(group, Set(process.Subject(msg))),
  )
}

fn init() -> actor.InitResult(State(msg, tag, group), Message(msg, tag, group)) {
  actor.Ready(
    State(
      registration: dict.new(),
      registered: set.new(),
      tagged: dict.new(),
      grouped: dict.new(),
    ),
    process.new_selector(),
  )
}

fn loop(
  message: Message(msg, tag, group),
  state: State(msg, tag, group),
) -> actor.Next(Message(msg, tag, group), State(msg, tag, group)) {
  case message {
    Register(registrant) -> {
      let selection = monitor(registrant)

      state
      |> into_registered(registrant)
      |> into_tagged(registrant)
      |> into_grouped(registrant)
      |> actor.Continue(selection)
    }

    Demonitor(monitor, pid, registrant) -> {
      // TODO: Check if demonitoring executes 1 time only because of multiple 
      // registrations.
      process.demonitor_process(monitor)

      state
      |> remove_from_registered(registrant)
      |> remove_from_tagged(registrant)
      |> remove_from_grouped(registrant)
      |> actor.Continue(option.None)
    }
  }
}

// //fn monitor(
// //  registration: Dict(process.Pid, Set(Registrant(msg, tag, group))),
// //  registrant: Registrant(msg, tag, group),
// //) -> option.Option(process.Selector(Message(msg, tag, group))) {
// //    // TODO: If demonitoring executes 1 time only this is not necessary.
// //  // Check if this process is already registered.
// //  let pid = process.subject_owner(registrant.subject)
// //
// //  case dict.get(registration, pid) {
// //    Ok(_locations) -> {
// //      // When process is already registered do nothing.
// //      option.None
// //    }
// //
// //    Error(Nil) -> {
// //      // When it is a new process, monitor it.
// //      let monitor = process.monitor_process(pid)
// //      let handle = fn(_: process.ProcessDown) {
// //        // This keeps track of registered subjects and where to look for them on de-registration.
// //        Demonitor(monitor, pid, monitor)
// //      }
// //
// //      option.Some(
// //        process.new_selector()
// //        |> process.selecting_process_down(monitor, handle),
// //      )
// //    }
// //  }
// //}

fn monitor(
  registrant: Registrant(msg, tag, group),
) -> option.Option(process.Selector(Message(msg, tag, group))) {
  let pid = process.subject_owner(registrant.subject)
  let monitor = process.monitor_process(pid)
  let on_process_down = fn(_: process.ProcessDown) {
    // This keeps track of registered subjects and where to look for them on de-registration.
    Demonitor(monitor, pid, registrant)
  }

  option.Some(
    process.new_selector()
    |> process.selecting_process_down(monitor, on_process_down),
  )
}

fn into_registration(
  state: State(msg, tag, group),
  registrant: Registrant(msg, tag, group),
) -> State(msg, tag, group) {
  todo
}

fn into_registered(
  state: State(msg, tag, group),
  registrant: Registrant(msg, tag, group),
) -> State(msg, tag, group) {
  let subjects = state.registered
  let subject = registrant.subject
  State(..state, registered: set.insert(subjects, subject))
}

fn into_tagged(
  state: State(msg, tag, group),
  registrant: Registrant(msg, tag, group),
) -> State(msg, tag, group) {
  case registrant {
    Registrant(tag: option.Some(tag), subject: subject, ..) -> {
      let subjects = state.tagged
      let tagged = dict.insert(subjects, tag, subject)
      State(..state, tagged: tagged)
    }

    Registrant(tag: option.None, ..) -> {
      state
    }
  }
}

fn into_grouped(
  state: State(msg, tag, group),
  registrant: Registrant(msg, tag, group),
) -> State(msg, tag, group) {
  let add_subject = fn(option) {
    case option {
      option.Some(subjects) -> set.insert(subjects, registrant.subject)
      option.None -> set.insert(set.new(), registrant.subject)
    }
  }

  case registrant {
    Registrant(group: option.Some(group), ..) -> {
      let grouped = dict.update(state.grouped, group, add_subject)
      State(..state, grouped: grouped)
    }

    Registrant(group: option.None, ..) -> {
      state
    }
  }
}

fn remove_from_registration(
  state: State(msg, tag, group),
  registrant: Registrant(msg, tag, group),
) -> State(msg, tag, group) {
  todo
}

fn remove_from_registered(
  state: State(msg, tag, group),
  registrant: Registrant(msg, tag, group),
) -> State(msg, tag, group) {
  todo
}

fn remove_from_tagged(
  state: State(msg, tag, group),
  registrant: Registrant(msg, tag, group),
) -> State(msg, tag, group) {
  todo
}

fn remove_from_grouped(
  state: State(msg, tag, group),
  registrant: Registrant(msg, tag, group),
) -> State(msg, tag, group) {
  todo
}
