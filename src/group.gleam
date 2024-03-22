import gleam/set.{type Set}
import gleam/dict.{type Dict}
import gleam/option.{None, Some}
import gleam/erlang/process.{
  type Pid, type ProcessDown, type ProcessMonitor, type Selector, type Subject,
}
import gleam/otp/actor
import gleam/io

type Registry(group, message) =
  Subject(Message(group, message))

pub opaque type Message(group, mssg) {
  Groups(client: Subject(List(group)))
  GroupedContent(client: Subject(List(Subject(mssg))), group: group)
  GroupedRegistrant(subject: Subject(mssg), group: group)
  Demonitor(pid: Pid)
}

type State(group, mssg) {
  State(
    // This indexes subjects through a reference, the source of thruth for finding a subject.
    //subjects: Dict(Reference, Subject(mssg)),
    // This tags multiple subject references under a group.
    groups: Dict(group, Set(Subject(mssg))),
    // When adding or de-registering, its useful to have quick access to the monitor ref and groups.
    monitors: Dict(Pid, #(ProcessMonitor, Set(#(group, Subject(mssg))))),
    // There's no way of retrieving previous selector from current process, so we manually track it here.
    selector: Selector(Message(group, mssg)),
  )
}

pub fn start() -> Result(Registry(name, mssg), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: handle_init,
    init_timeout: 10,
    loop: handle_message,
  ))
}

fn handle_init() {
  let selector = process.new_selector()
  let state =
    State(groups: dict.new(), monitors: dict.new(), selector: selector)

  actor.Ready(state, selector)
}

fn handle_message(message: Message(name, message), state: State(name, message)) {
  case message {
    Groups(client) -> {
      let groups = dict.keys(state.groups)
      process.send(client, groups)
      actor.continue(state)
    }

    GroupedContent(client, group) -> {
      let subjects = case dict.get(state.groups, group) {
        Ok(subjects) -> set.to_list(subjects)
        Error(Nil) -> []
      }

      process.send(client, subjects)
      actor.continue(state)
    }

    GroupedRegistrant(subject, group) -> {
      // Check if this subject is already registered.
      let pid = process.subject_owner(subject)
      let record = case dict.get(state.monitors, pid) {
        Ok(#(monitor, membership_refs)) -> {
          // If subject is already registered do nothing.
          #(monitor, membership_refs, state.selector, None)
        }

        Error(Nil) -> {
          // If subject is a new process, monitor it.
          let monitor = process.monitor_process(pid)

          // Build the selector to track down if monitored process goes down
          let handle = fn(_process: ProcessDown) { Demonitor(pid) }
          let selector =
            process.selecting_process_down(state.selector, monitor, handle)

          #(monitor, set.new(), selector, Some(selector))
        }
      }

      // Store the new monitors, subjects and selector as a reference.
      let #(monitor, membership_refs, selector, selection) = record

      let groups =
        dict.update(state.groups, group, fn(option) {
          case option {
            Some(subjects) -> set.insert(subjects, subject)
            None -> set.insert(set.new(), subject)
          }
        })

      let monitors =
        dict.insert(state.monitors, pid, #(
          monitor,
          membership_refs
          |> set.insert(#(group, subject)),
        ))

      actor.Continue(State(groups, monitors, selector), selection)
    }

    // Tal vez un approach estilo Base de Datos funcionaría mejor con Pattern matching.
    Demonitor(pid) -> {
      case dict.get(state.monitors, pid) {
        Ok(#(monitor, membership_refs)) -> {
          // Demonitor process
          process.demonitor_process(monitor)

          let groups =
            set.fold(membership_refs, state.groups, fn(groups, membership_ref) {
              let #(group, subject) = membership_ref

              case dict.get(state.groups, group) {
                Ok(subjects) -> {
                  dict.insert(state.groups, group, set.delete(subjects, subject),
                  )
                }

                Error(Nil) -> {
                  state.groups
                }
              }
            })

          let monitors = dict.delete(state.monitors, pid)

          let state = State(..state, groups: groups, monitors: monitors)
          actor.continue(state)
        }

        Error(Nil) -> {
          io.print("pid was not in registry")
          io.debug(pid)

          actor.continue(state)
        }
      }
      todo
    }
  }
}
