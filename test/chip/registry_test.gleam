import chip/registry
import counter
import gleam/erlang/process
import gleam/int
import gleam/otp/supervisor
import gleam/result
import gleeunit

//*---------------- start tests -===---------------*//

pub fn can_start_registry_test() {
  let assert Ok(_registry) = registry.start()
}

//*---------------- register tests ----------------*//

pub fn can_register_subject_test() {
  let assert Ok(registry) = registry.start()
  let subject_1: process.Subject(Nil) = process.new_subject()
  let subject_2: process.Subject(Nil) = process.new_subject()
  let subject_3: process.Subject(Nil) = process.new_subject()

  // manually register all subjects
  let assert Nil = registry.register(registry, subject_1, "test-subject-1")
  let assert Nil = registry.register(registry, subject_2, "test-subject-2")
  let assert Nil = registry.register(registry, subject_3, "test-subject-3")
}

//*---------------- find tests -------------------*//

pub fn can_retrieve_individual_subject_test() {
  let assert Ok(registry) = registry.start()
  let subject_1: process.Subject(Nil) = process.new_subject()
  let subject_2: process.Subject(Nil) = process.new_subject()
  let subject_3: process.Subject(Nil) = process.new_subject()

  // manually register all subjects
  registry.register(registry, subject_1, "test-subject-1")
  registry.register(registry, subject_2, "test-subject-2")
  registry.register(registry, subject_3, "test-subject-3")

  let assert Ok(_subject) = registry.find(registry, "test-subject-1")
  let assert Ok(_subject) = registry.find(registry, "test-subject-2")
  let assert Ok(_subject) = registry.find(registry, "test-subject-3")
}

pub fn cannot_retrieve_with_unused_name_test() {
  let assert Ok(registry) = registry.start()

  let assert Error(Nil) = registry.find(registry, "nothing")
}

//*---------------- other tests ------------------*//

pub fn subject_eventually_deregisters_after_process_dies_test() {
  let assert Ok(registry) = registry.start()
  let registry: Registry = registry

  // start a new counter registry
  let assert Ok(counter) = counter.start(0)
  registry.register(registry, counter, "counter")

  // stops the counter actor
  counter.stop(counter)

  // eventually the counter should be automatically de-registered
  let find = fn() { registry.find(registry, "counter") }
  let assert True = until(find, is: Error(Nil), for: 50)
}

pub fn registering_works_along_supervisor_test() {
  let assert Ok(registry) = registry.start()
  let registry: Registry = registry

  // for each child the supervisor will increment the name and count
  let children = fn(children) {
    children
    |> supervisor.add(child_spec(registry))
    |> supervisor.add(child_spec(registry))
    |> supervisor.add(child_spec(registry))
  }

  // start the supervisor
  let assert Ok(_supervisor) =
    supervisor.start_spec(supervisor.Spec(
      argument: 1,
      frequency_period: 1,
      max_frequency: 5,
      init: children,
    ))

  // assert we can retrieve individual subjects
  let assert Ok(counter_1) = registry.find(registry, "counter-1")
  let assert 1 = counter.current(counter_1)

  let assert Ok(counter_2) = registry.find(registry, "counter-2")
  let assert 2 = counter.current(counter_2)

  let assert Ok(counter_3) = registry.find(registry, "counter-3")
  let assert 3 = counter.current(counter_3)

  // assert we're not able to retrieve non-registered subjects
  let assert Error(Nil) = registry.find(registry, "counter-4")

  // assert subject is restarted by the supervisor after actor dies
  counter.stop(counter_2)

  let different_subject = fn() {
    case registry.find(registry, "counter-2") {
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
  process.Subject(registry.Message(String, counter.Message))

fn child_spec(registry) {
  // an actor will be spawned and immediately registered after success
  let start = fn(id) {
    let initial_count = id
    let name = "counter-" <> int.to_string(id)

    use subject <- result.try(counter.start(initial_count))
    let Nil = registry.register(registry, subject, name)
    Ok(subject)
  }

  // increment each registration by 1 in the supervisor
  let updater = fn(id, _subject) { id + 1 }

  // compose the updater and start function into a spec for the supervisor
  supervisor.worker(start)
  |> supervisor.returning(updater)
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
