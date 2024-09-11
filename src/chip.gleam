//// Chip is a local process registry that plays along with Gleam's `Subject` type for referencing
//// erlang processes. It can hold to a set of subjects to later reference individually or dispatch 
//// a callback as a group. Will also automatically delist dead processes.

import gleam/dict
import gleam/dynamic
import gleam/erlang
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/set

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
/// let registry: process.Subject(chip.Message(Event, Id, Topic))
/// ```
/// 
/// By specifying the types we can document the kind of registry we are working with.
pub type Registry(msg, tag, group) =
  process.Subject(Message(msg, tag, group))

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

/// Creates a new "chip" that can be tagged, grouped and registered. 
/// 
/// ## Example
/// 
/// ```gleam
/// chip.new(subject)
/// ```
pub fn new(subject: process.Subject(msg)) -> Chip(msg, tag, group) {
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
) -> Result(process.Subject(msg), Nil) {
  // TODO: May be obtained from ETS directly
  // TODO: Time out is to fragile here
  process.call(registry, Lookup(_, tag), 5000)
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
  callback: fn(process.Subject(msg)) -> x,
) -> Nil {
  // TODO: May be obtained from ETS directly
  // TODO: Time out is to fragile here
  let subjects = process.call(registry, Members(_), 5000)
  list.each(subjects, callback)
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
  callback: fn(process.Subject(msg)) -> x,
) -> Nil {
  let subjects = process.call(registry, MembersAt(_, group), 5000)
  list.each(subjects, callback)
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

/// Chip's internal message type.
pub opaque type Message(msg, tag, group) {
  Register(Chip(msg, tag, group))
  Demonitor(erlang.Reference, process.Pid)
  Lookup(process.Subject(Result(process.Subject(msg), Nil)), tag)
  Members(process.Subject(List(process.Subject(msg))))
  MembersAt(process.Subject(List(process.Subject(msg))), group)
  Stop
}

/// A "chip" used for registration. Check the [new](#new) function.
pub opaque type Chip(msg, tag, group) {
  Chip(
    subject: process.Subject(msg),
    tag: option.Option(tag),
    group: option.Option(group),
  )
}

// TODO: Previous ideas:
// * Use metadata, given when a process is registred or at dispatch.
type State(msg, tag, group) {
  State(
    // Keeps track of registrations so its easier to find subjects by pid.
    index: dict.Dict(process.Pid, set.Set(Chip(msg, tag, group))),
    // Store for all registered subjects.
    registered: set.Set(process.Subject(msg)),
    // Store for all tagged subjects. 
    tagged: dict.Dict(tag, process.Subject(msg)),
    // Store for all grouped subjects.
    grouped: dict.Dict(group, set.Set(process.Subject(msg))),
  )
}

type ProcessDown {
  ProcessDown(monitor: erlang.Reference, pid: process.Pid)
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
        // TODO: Have a noop operation? 
        //       Does this selector affect the actor's messages?
        //       Resend message to self?
        io.debug("selecting_anything callback got an Error(Nil), message:")
        io.debug(message)
        panic as "Malformed down message."
      }
    }
  }

  actor.Ready(
    State(
      index: dict.new(),
      registered: set.new(),
      tagged: dict.new(),
      grouped: dict.new(),
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
      let state = insert(state, registrant)
      actor.Continue(state, option.None)
    }

    Demonitor(monitor, pid) -> {
      let state = delete(state, monitor, pid)
      actor.Continue(state, option.None)
    }

    Lookup(client, tag) -> {
      let result = dict.get(state.tagged, tag)
      process.send(client, result)
      actor.Continue(state, option.None)
    }

    Members(client) -> {
      let subjects = set.to_list(state.registered)
      process.send(client, subjects)
      actor.Continue(state, option.None)
    }

    MembersAt(client, group) -> {
      let subjects = case dict.get(state.grouped, group) {
        Ok(subjects) -> set.to_list(subjects)
        Error(Nil) -> []
      }

      process.send(client, subjects)
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
) -> State(msg, tag, group) {
  // Monitor the Subject's process.
  let pid = process.subject_owner(registrant.subject)
  let _monitor = process.monitor_process(pid)

  state
  |> into_index(registrant)
  |> into_registered(registrant)
  |> into_tagged(registrant)
  |> into_grouped(registrant)
}

fn into_index(
  state: State(msg, tag, group),
  registrant: Chip(msg, tag, group),
) -> State(msg, tag, group) {
  let pid = process.subject_owner(registrant.subject)

  let registrants = case dict.get(state.index, pid) {
    Ok(registrants) -> {
      set.insert(registrants, registrant)
    }

    Error(Nil) -> {
      set.new() |> set.insert(registrant)
    }
  }

  let index = dict.insert(state.index, pid, registrants)

  State(..state, index: index)
}

fn into_registered(
  state: State(msg, tag, group),
  registrant: Chip(msg, tag, group),
) -> State(msg, tag, group) {
  let subjects = state.registered
  let subject = registrant.subject
  State(..state, registered: set.insert(subjects, subject))
}

fn into_tagged(
  state: State(msg, tag, group),
  registrant: Chip(msg, tag, group),
) -> State(msg, tag, group) {
  case registrant {
    Chip(tag: option.Some(tag), subject: subject, ..) -> {
      let subjects = state.tagged
      let tagged = dict.insert(subjects, tag, subject)
      State(..state, tagged: tagged)
    }

    Chip(tag: option.None, ..) -> {
      state
    }
  }
}

fn into_grouped(
  state: State(msg, tag, group),
  registrant: Chip(msg, tag, group),
) -> State(msg, tag, group) {
  let add_subject = fn(option) {
    case option {
      option.Some(subjects) -> set.insert(subjects, registrant.subject)
      option.None -> set.insert(set.new(), registrant.subject)
    }
  }

  case registrant {
    Chip(group: option.Some(group), ..) -> {
      let grouped = dict.upsert(state.grouped, group, add_subject)
      State(..state, grouped: grouped)
    }

    Chip(group: option.None, ..) -> {
      state
    }
  }
}

fn delete(
  state: State(msg, tag, group),
  monitor: erlang.Reference,
  pid: process.Pid,
) -> State(msg, tag, group) {
  let Nil = demonitor(monitor)

  case dict.get(state.index, pid) {
    Ok(registrants) -> {
      set.fold(over: registrants, from: state, with: fn(state, registrant) {
        state
        |> remove_from_registered(registrant)
        |> remove_from_tagged(registrant)
        |> remove_from_grouped(registrant)
      })
      |> remove_from_index(pid)
    }

    Error(Nil) -> {
      state
    }
  }
}

fn remove_from_index(
  state: State(msg, tag, group),
  pid: process.Pid,
) -> State(msg, tag, group) {
  let index = dict.delete(state.index, pid)
  State(..state, index: index)
}

fn remove_from_registered(
  state: State(msg, tag, group),
  registrant: Chip(msg, tag, group),
) -> State(msg, tag, group) {
  let registered = set.delete(state.registered, registrant.subject)
  State(..state, registered: registered)
}

fn remove_from_tagged(
  state: State(msg, tag, group),
  registrant: Chip(msg, tag, group),
) -> State(msg, tag, group) {
  case registrant {
    Chip(tag: option.Some(tag), ..) -> {
      let tagged = dict.delete(state.tagged, tag)
      State(..state, tagged: tagged)
    }

    Chip(tag: option.None, ..) -> {
      state
    }
  }
}

fn remove_from_grouped(
  state: State(msg, tag, group),
  registrant: Chip(msg, tag, group),
) -> State(msg, tag, group) {
  case registrant {
    Chip(group: option.Some(group), ..) -> {
      case dict.get(state.grouped, group) {
        Ok(subjects) -> {
          let subjects = set.delete(subjects, registrant.subject)
          let grouped = dict.insert(state.grouped, group, subjects)
          State(..state, grouped: grouped)
        }

        Error(Nil) -> {
          panic as "Impossible state, group was not found on remove_from_grouped."
        }
      }
    }

    Chip(group: option.None, ..) -> {
      state
    }
  }
}

@external(erlang, "chip_erlang_ffi", "decode_down_message")
fn decode_down_message(message: dynamic.Dynamic) -> Result(ProcessDown, Nil)

@external(erlang, "chip_erlang_ffi", "demonitor")
fn demonitor(reference: erlang.Reference) -> Nil
