//// assert we can retrieve individual subjects
//// assert we're not able to retrieve non-registered subjects
//// assert subject is restarted by the supervisor after actor dies

import chip/single
import counter
import gleam/erlang/process
import gleam/int
import gleam/otp/supervisor
import gleam/result
import gleeunit

//*---------------- start tests -===---------------*//

pub fn can_start_registry_test() {
  let assert Ok(_registry) = single.start()
}

//*---------------- register tests ----------------*//

pub fn can_register_subject_test() {
  let assert Ok(registry) = single.start()
  let subject_1: process.Subject(Nil) = process.new_subject()
  let subject_2: process.Subject(Nil) = process.new_subject()
  let subject_3: process.Subject(Nil) = process.new_subject()

  // manually register all subjects
  let assert Nil = single.register(registry, subject_1, "test-subject-1")
  let assert Nil = single.register(registry, subject_2, "test-subject-2")
  let assert Nil = single.register(registry, subject_3, "test-subject-3")
}

//*---------------- find tests -------------------*//

pub fn can_retrieve_individual_subject_test() {
  let assert Ok(registry) = single.start()
  let subject_1: process.Subject(Nil) = process.new_subject()
  let subject_2: process.Subject(Nil) = process.new_subject()
  let subject_3: process.Subject(Nil) = process.new_subject()

  // manually register all subjects
  single.register(registry, subject_1, "test-subject-1")
  single.register(registry, subject_2, "test-subject-2")
  single.register(registry, subject_3, "test-subject-3")

  let assert Ok(_subject) = single.find(registry, "test-subject-1")
  let assert Ok(_subject) = single.find(registry, "test-subject-2")
  let assert Ok(_subject) = single.find(registry, "test-subject-3")
}

pub fn cannot_retrieve_with_unused_name_test() {
  let assert Ok(registry) = single.start()

  let assert Error(Nil) = single.find(registry, "nothing")
}

//*---------------- other tests ------------------*//

pub fn subject_eventually_deregisters_after_process_dies_test() {
  let assert Ok(registry) = single.start()
  let registry: Registry = registry

  // start a new counter registry
  let assert Ok(counter) = counter.start(0)
  single.register(registry, counter, "counter")

  // stops the counter actor
  counter.stop(counter)

  // eventually the counter should be automatically de-registered
  let find = fn() { single.find(registry, "counter") }
  let assert True = until(find, is: Error(Nil), for: 50)
}

pub fn registering_works_along_supervisor_test() {
  let self = process.new_subject()

  let child_spec_registry = fn() {
    // the registry will be spawned and will send its subject to current process
    let start = fn(_param) {
      use registry <- result.try(single.start())
      process.send(self, registry)
      Ok(registry)
    }

    // for subsequent calls pass-on the registry  
    let updater = fn(_param, registry) { registry }

    // compose the start and updater into a child spec for the supervisor
    supervisor.worker(start)
    |> supervisor.returning(updater)
  }

  let child_spec_counter = fn() {
    // then counter will be spawned and registered
    let start = fn(param) {
      let #(registry, id) = param
      let initial_count = id
      let name = "counter-" <> int.to_string(id)

      use counter <- result.try(counter.start(initial_count))
      let Nil = single.register(registry, counter, name)
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
      |> supervisor.add(child_spec_registry())
      |> supervisor.add(
        supervisor.supervisor(fn(registry) {
          supervisor.start_spec(
            supervisor.Spec(
              argument: #(registry, 1),
              max_frequency: 5,
              frequency_period: 1,
              init: fn(children) {
                children
                |> supervisor.add(child_spec_counter())
                |> supervisor.add(child_spec_counter())
                |> supervisor.add(child_spec_counter())
              },
            ),
          )
        }),
      )
    })

  // wait for the registry to initialize and send back its Subject
  let assert Ok(registry) = process.receive(self, 50)

  // assert we can retrieve individual subjects
  let assert Ok(counter_1) = single.find(registry, "counter-1")
  let assert 1 = counter.current(counter_1)

  let assert Ok(counter_2) = single.find(registry, "counter-2")
  let assert 2 = counter.current(counter_2)

  let assert Ok(counter_3) = single.find(registry, "counter-3")
  let assert 3 = counter.current(counter_3)

  // assert we're not able to retrieve non-registered subjects
  let assert Error(Nil) = single.find(registry, "counter-4")

  // assert subject is restarted by the supervisor after actor dies
  counter.stop(counter_2)

  let different_subject = fn() {
    case single.find(registry, "counter-2") {
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
  process.Subject(single.Message(String, counter.Message))

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
