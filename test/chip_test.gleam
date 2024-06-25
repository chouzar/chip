import chip
import counter
import gleam/erlang/process
import gleam/int
import gleam/otp/supervisor
import gleam/result.{try}
import gleeunit

//*---------------- lookup tests -------------------*//

pub fn can_retrieve_individual_subjects_test() {
  let assert Ok(registry) = chip.start()

  let subject_1: process.Subject(Nil) = process.new_subject()
  let subject_2: process.Subject(Nil) = process.new_subject()
  let subject_3: process.Subject(Nil) = process.new_subject()

  chip.new(subject_1) |> chip.tag(1) |> chip.register(registry, _)
  chip.new(subject_2) |> chip.tag(2) |> chip.register(registry, _)
  chip.new(subject_2) |> chip.tag(3) |> chip.register(registry, _)

  let assert Ok(_subject) = chip.find(registry, 1)
  let assert Ok(_subject) = chip.find(registry, 2)
  let assert Ok(_subject) = chip.find(registry, 3)
}

pub fn cannot_retrieve_subject_if_not_registered() {
  let assert Ok(registry) = chip.start()

  let assert Error(Nil) = chip.find(registry, "nothing")
}

//*---------------- dispatch tests --------------*//

pub fn dispatch_is_applied_over_subjects_test() {
  let assert Ok(registry) = chip.start()
  let registry: chip.Registry(counter.Message, Int, Group) = registry

  
  let assert Ok(counter_1) = counter.start(1)
  let assert Ok(counter_2) = counter.start(2)
  let assert Ok(counter_3) = counter.start(3)
  let assert Ok(counter_4) = counter.start(4)
  let assert Ok(counter_5) = counter.start(5)
  let assert Ok(counter_6) = counter.start(6)

  chip.new(counter_1) |> chip.group(GroupA) |> chip.register(registry, _)
  chip.new(counter_2) |> chip.group(GroupB) |> chip.register(registry, _)
  chip.new(counter_3) |> chip.group(GroupB) |> chip.register(registry, _)
  chip.new(counter_4) |> chip.group(GroupC) |> chip.register(registry, _)
  chip.new(counter_5) |> chip.group(GroupC) |> chip.register(registry, _)
  chip.new(counter_6) |> chip.group(GroupC) |> chip.register(registry, _)

  chip.dispatch(registry, fn(subject) { counter.increment(subject) })

  let assert 2 = counter.current(counter_1)
  let assert 3 = counter.current(counter_2)
  let assert 4 = counter.current(counter_3)
  let assert 5 = counter.current(counter_4)
  let assert 6 = counter.current(counter_5)
  let assert 7 = counter.current(counter_6)
}

pub fn dispatch_is_applied_over_groups_test() {
  let assert Ok(registry) = chip.start()
  let registry: chip.Registry(counter.Message, Int, Group) = registry

  let assert Ok(counter_1) = counter.start(1)
  let assert Ok(counter_2) = counter.start(2)
  let assert Ok(counter_3) = counter.start(3)
  let assert Ok(counter_4) = counter.start(4)
  let assert Ok(counter_5) = counter.start(5)
  let assert Ok(counter_6) = counter.start(6)

  chip.new(counter_1) |> chip.group(GroupA) |> chip.register(registry, _)
  chip.new(counter_2) |> chip.group(GroupB) |> chip.register(registry, _)
  chip.new(counter_3) |> chip.group(GroupB) |> chip.register(registry, _)
  chip.new(counter_4) |> chip.group(GroupC) |> chip.register(registry, _)
  chip.new(counter_5) |> chip.group(GroupC) |> chip.register(registry, _)
  chip.new(counter_6) |> chip.group(GroupC) |> chip.register(registry, _)

  chip.dispatch_group(registry, GroupA, fn(subject) {
    counter.increment(subject)
  })

  chip.dispatch_group(registry, GroupB, fn(subject) {
    counter.increment(subject)
    counter.increment(subject)
  })

  chip.dispatch_group(registry, GroupC, fn(subject) {
    counter.increment(subject)
    counter.increment(subject)
    counter.increment(subject)
  })

  let assert 2 = counter.current(counter_1)
  let assert 4 = counter.current(counter_2)
  let assert 5 = counter.current(counter_3)
  let assert 7 = counter.current(counter_4)
  let assert 8 = counter.current(counter_5)
  let assert 9 = counter.current(counter_6)
}

//*---------------- other tests ------------------*//

pub fn subject_eventually_deregisters_after_process_dies_test() {
  let assert Ok(registry) = chip.start()
  let registry: chip.Registry(counter.Message, String, Nil) = registry

  let assert Ok(counter) = counter.start(0)
  chip.new(counter) |> chip.tag("counter") |> chip.register(registry, _)

  // stops the counter actor
  counter.stop(counter)

  // eventually the counter should be automatically de-registered
  let find = fn() { chip.find(registry, "counter") }
  let assert True = until(find, is: Error(Nil), for: 50)
}

pub fn registering_works_along_supervisor_test() {
  let self = process.new_subject()

  let childspec_registry = fn() {
    // the registry will be spawned and will send its subject to current process
    let start = fn(_param) {
      use registry <- try(chip.start())
      process.send(self, registry)
      Ok(registry)
    }

    // for subsequent calls pass-on the registry  
    let updater = fn(_param, registry) { registry }

    // compose the start and updater into a child spec for the supervisor
    supervisor.worker(start)
    |> supervisor.returning(updater)
  }

  let childspec_counter = fn() {
    // then counter will be spawned and registered
    let start = fn(param) {
      let #(registry, id) = param
      let count = id
      let name = "counter-" <> int.to_string(id)

      use counter <- try(counter.start(count))
      chip.new(counter) |> chip.tag(name) |> chip.register(registry, _)
      Ok(counter)
    }

    // for subsequent calls pass-on the registry and increment the id 
    let updater = fn(param, _subject) {
      let #(registry, id) = param
      #(registry, id + 1)
    }

    // compose the start and updater into a child spec for the supervisor
    supervisor.worker(start)
    |> supervisor.returning(updater)
  }

  // start the supervisor
  let assert Ok(_supervisor) =
    supervisor.start(fn(children) {
      children
      |> supervisor.add(childspec_registry())
      |> supervisor.add(
        supervisor.supervisor(fn(registry) {
          supervisor.start_spec(
            supervisor.Spec(
              argument: #(registry, 1),
              max_frequency: 5,
              frequency_period: 1,
              init: fn(children) {
                children
                |> supervisor.add(childspec_counter())
                |> supervisor.add(childspec_counter())
                |> supervisor.add(childspec_counter())
              },
            ),
          )
        }),
      )
    })

  // wait for the registry to initialize and send back its Subject
  let assert Ok(registry) = process.receive(self, 50)

  // assert we can retrieve individual subjects
  let assert Ok(counter_1) = chip.find(registry, "counter-1")
  let assert 1 = counter.current(counter_1)

  let assert Ok(counter_2) = chip.find(registry, "counter-2")
  let assert 2 = counter.current(counter_2)

  let assert Ok(counter_3) = chip.find(registry, "counter-3")
  let assert 3 = counter.current(counter_3)

  // assert we're not able to retrieve non-registered subjects
  let assert Error(Nil) = chip.find(registry, "counter-4")

  // assert subject is restarted by the supervisor after actor dies
  counter.stop(counter_2)

  let different_subject = fn() {
    case chip.find(registry, "counter-2") {
      Ok(counter) if counter != counter_2 -> True
      Ok(_) -> False
      Error(_) -> False
    }
  }

  let assert True = until(different_subject, is: True, for: 50)
}

//*---------------- Test helpers ----------------*//

pub fn main() {
  gleeunit.main()
}

type Registry =
  process.Subject(chip.Message(counter.Message, Int, Group))

type Group {
  GroupA
  GroupB
  GroupC
}

fn until(condition, is outcome, for milliseconds) -> Bool {
  case milliseconds, condition() {
    _milliseconds, result if result == outcome -> {
      True
    }

    milliseconds, _result if milliseconds > 0 -> {
      process.sleep(5)
      until(condition, outcome, milliseconds - 5)
    }

    _milliseconds, _result -> {
      False
    }
  }
}