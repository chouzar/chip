//// Chip is a local process registry that plays along with Gleam's `Subject` type for referencing
//// erlang processes. It can hold to a set of subjects to later reference individually or dispatch 
//// a callback as a group. Will also automatically delist dead processes.

import gleam/dynamic
import gleam/erlang
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/otp/task

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
  // TODO: Add a concurrency option for dispatch
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
  // TODO: Time out is to fragile here
  // TODO: How to make these calls fully concurrent?
  let table = process.call(registry, Find(_), 500)

  // Error in process <0.89.0> with exit value:
  //   {{case_clause,'$end_of_table'},
  //    [{chip_erlang_ffi,handle_search,1,
  //                      [{file,"/Users/chouzar/Bench/Projects/chip/build/dev/erlang/chip/_gleam_artefacts/chip_erlang_ffi.erl"},
  //                       {line,18}]},

  // TODO: Match with end of table
  case ets_lookup(table, tag) {
    [#(_tag, _pid, subject)] -> Ok(subject)
    [] -> Error(Nil)
    _other -> panic as "Impossible lookup on a tagged table"
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
  callback: fn(process.Subject(msg)) -> Nil,
) -> Nil {
  // TODO: Change the callback return type to be generic and not only Nil
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
  callback: fn(process.Subject(msg)) -> Nil,
) -> Nil {
  // TODO: Change the callback return type to be generic and not only Nil
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

/// Chip's internal message type.
pub opaque type Message(msg, tag, group) {
  Register(Chip(msg, tag, group))
  Demonitor(erlang.Reference, process.Pid)
  Find(process.Subject(erlang.Reference))
  Dispatch(fn(process.Subject(msg)) -> Nil)
  DispatchGroup(fn(process.Subject(msg)) -> Nil, group)
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
    // This config dictates how many max tasks to launch on a dispatch
    max_concurrency: Int,
    // ETS table references
    registered: erlang.Reference,
    tagged: erlang.Reference,
    grouped: erlang.Reference,
  )
}

type ProcessDown {
  ProcessDown(monitor: erlang.Reference, pid: process.Pid)
}

type Table {
  ChipRegistry
  ChipRegistryTagged
  ChipRegistryGrouped
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
        io.debug("selecting_anything callback got an Error(Nil), message: ")
        io.debug(message)
        panic as "Malformed down message."
      }
    }
  }

  actor.Ready(
    State(
      max_concurrency: 8,
      registered: ets_new(ChipRegistry, [Protected, Set]),
      tagged: ets_new(ChipRegistryTagged, [Protected, Set]),
      grouped: ets_new(ChipRegistryGrouped, [Protected, Bag]),
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
      // TODO: Find a way to share this table reference without asking 
      //       * Maybe return the reference within the init
      //       * Modify the API to retrieve the table independently
      //       * Make it so this returns a task that must be awaited on. 
      process.send(client, state.tagged)
      actor.Continue(state, option.None)
    }

    Dispatch(callback) -> {
      // TODO: A better option may be to iterate through the table
      // TODO: Must add a cap to the number of spawned tasks
      // TODO: Should dispatch notify when done?
      // TODO: This dispatch should be done out of process

      let get_subject = fn(object) {
        let assert [subject] = object
        subject
      }

      start_dispatch(
        state.registered,
        #(match_into(1), match_any()),
        get_subject,
        callback,
        8,
      )

      actor.Continue(state, option.None)
    }

    DispatchGroup(callback, group) -> {
      // TODO: A better option may be to iterate through the table
      // TODO: Must add a cap to the number of spawned tasks
      // TODO: Should dispatch notify when done?
      // TODO: This dispatch should be done out of process

      let get_subject = fn(object) {
        let assert [subject] = object
        subject
      }

      start_dispatch(
        state.grouped,
        #(group, match_any(), match_into(1)),
        get_subject,
        callback,
        8,
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

  let assert True = ets_insert(state.registered, #(registrant.subject, pid))

  option.map(registrant.tag, fn(tag) {
    let assert True = ets_insert(state.tagged, #(tag, pid, registrant.subject))
  })

  option.map(registrant.group, fn(group) {
    let assert True =
      ets_insert(state.grouped, #(group, pid, registrant.subject))
  })

  Nil
}

fn delete(
  state: State(msg, tag, group),
  monitor: erlang.Reference,
  pid: process.Pid,
) -> Nil {
  let Nil = demonitor(monitor)

  let assert True = ets_match_delete(state.registered, #(match_any(), pid))
  let assert True =
    ets_match_delete(state.tagged, #(match_any(), pid, match_any()))
  let assert True =
    ets_match_delete(state.grouped, #(match_any(), pid, match_any()))

  Nil
}

fn start_dispatch(
  table: erlang.Reference,
  pattern: pattern,
  decode_record: fn(object) -> process.Subject(msg),
  task: fn(process.Subject(msg)) -> Nil,
  concurrency: Int,
) -> Nil {
  // TODO: Currently this is very fragile. Work to improve this: 
  // * Chip shouldn't stop working, waiting for these tasks to finish.
  // * Tasks should be spawned on batches, to not overload the system.
  // * Each task should be monitored by a process. 
  //   * On success, each task would notify the monitor.  
  //   * On error, each task should log or have a behaviour to report to.  
  // 
  // NOTE: Should this maybe be processed within actor messages?

  table
  |> search(pattern, concurrency)
  |> handle_dispatch_results(decode_record, task)
}

fn continue_dispatch(
  step: Step,
  decode_record: fn(object) -> process.Subject(msg),
  task: fn(process.Subject(msg)) -> Nil,
) -> Nil {
  search_continuation(step)
  |> handle_dispatch_results(decode_record, task)
}

fn handle_dispatch_results(
  lookup: Search(object),
  decode_record: fn(object) -> process.Subject(msg),
  task: fn(process.Subject(msg)) -> Nil,
) {
  case lookup {
    Partial(objects, step) -> {
      objects
      |> list.map(decode_record)
      |> run_batch(task)

      continue_dispatch(step, decode_record, task)
    }

    EndOfTable(objects) -> {
      objects
      |> list.map(decode_record)
      |> run_batch(task)
    }
  }
}

fn run_batch(
  subjects: List(process.Subject(msg)),
  callback: fn(process.Subject(msg)) -> Nil,
) -> Nil {
  // TODO: We need a user defined waiting time.
  subjects
  |> list.map(fn(subject) { task.async(fn() { callback(subject) }) })
  |> list.each(fn(task) { task.await(task, 100) })
}

// ETS Code ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

type Option {
  Protected
  Set
  Bag
}

type Step

type Search(object) {
  Partial(List(object), Step)
  EndOfTable(List(object))
}

// TODO; Create Pattern types to match on easily

// rename into select
fn match_into(n: Int) -> atom.Atom {
  atom.create_from_string("$" <> int.to_string(n))
}

fn match_any() -> atom.Atom {
  atom.create_from_string("_")
}

@external(erlang, "chip_erlang_ffi", "search")
fn search(
  table: erlang.Reference,
  pattern: pattern,
  limit: Int,
) -> Search(objects)

@external(erlang, "chip_erlang_ffi", "search")
fn search_continuation(step: Step) -> Search(objects)

@external(erlang, "ets", "new")
fn ets_new(table: Table, options: List(Option)) -> erlang.Reference

@external(erlang, "ets", "insert")
fn ets_insert(table: erlang.Reference, value: value) -> Bool

@external(erlang, "ets", "lookup")
fn ets_lookup(table: erlang.Reference, key: key) -> List(object)

@external(erlang, "ets", "match_delete")
fn ets_match_delete(table: erlang.Reference, pattern: pattern) -> Bool

//@external(erlang, "ets", "match")
//fn ets_match(table: erlang.Reference, pattern: pattern) -> List(object)
//
// @external(erlang, "ets", "delete")
// fn ets_delete(table: erlang.Reference, key: key) -> Bool
//
//@external(erlang, "ets", "tab2list")
//fn ets_all(table: erlang.Reference) -> List(object)
//
//@external(erlang, "ets", "member")
//fn ets_member(table: erlang.Reference, key: key) -> Bool
//
//@external(erlang, "ets", "delete")
//fn ets_kill(table: erlang.Reference) -> Bool
//
//@external(erlang, "erlang", "spawn")
//fn spawn(f: fn() -> x) -> process.Pid
//
//fn end_of_table() -> atom.Atom {
//  atom.create_from_string("$end_of_table")
//}
//

// Other helpers

@external(erlang, "chip_erlang_ffi", "decode_down_message")
fn decode_down_message(message: dynamic.Dynamic) -> Result(ProcessDown, Nil)

@external(erlang, "chip_erlang_ffi", "demonitor")
fn demonitor(reference: erlang.Reference) -> Nil
