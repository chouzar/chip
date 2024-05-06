import chip
import counter
import gleam/erlang/process
import gleam/int
import gleam/otp/supervisor
import gleam/result
import gleeunit

//*---------------- start tests -===---------------*//

pub fn can_start_registry_test() {
  let assert Ok(_registry) = chip.start()
}

//*---------------- register tests ----------------*//

pub fn can_register_subject_test() {
  let assert Ok(registry) = chip.start()
  let subject_1: process.Subject(Nil) = process.new_subject()
  let subject_2: process.Subject(Nil) = process.new_subject()
  let subject_3: process.Subject(Nil) = process.new_subject()

  // manually register all subjects
  let assert Nil = chip.register(registry, subject_1, "test-subject-1")
  let assert Nil = chip.register(registry, subject_2, "test-subject-2")
  let assert Nil = chip.register(registry, subject_3, "test-subject-3")
}

//*---------------- find tests -------------------*//

pub fn can_retrieve_individual_subject_test() {
  let assert Ok(registry) = chip.start()
  let subject_1: process.Subject(Nil) = process.new_subject()
  let subject_2: process.Subject(Nil) = process.new_subject()
  let subject_3: process.Subject(Nil) = process.new_subject()

  // manually register all subjects
  chip.register(registry, subject_1, "test-subject-1")
  chip.register(registry, subject_2, "test-subject-2")
  chip.register(registry, subject_3, "test-subject-3")

  let assert Ok(_subject) = chip.find(registry, "test-subject-1")
  let assert Ok(_subject) = chip.find(registry, "test-subject-2")
  let assert Ok(_subject) = chip.find(registry, "test-subject-3")
}

pub fn cannot_retrieve_with_unused_name_test() {
  let assert Ok(registry) = chip.start()

  let assert Error(Nil) = chip.find(registry, "nothing")
}

//*---------------- group tests -----------------*//

pub fn can_group_subjects_test() {
  let assert Ok(registry) = chip.start()
  let subject_1: process.Subject(Nil) = process.new_subject()
  let subject_2: process.Subject(Nil) = process.new_subject()
  let subject_3: process.Subject(Nil) = process.new_subject()

  let assert Nil = chip.group(registry, subject_1, GroupA)
  let assert Nil = chip.group(registry, subject_2, GroupB)
  let assert Nil = chip.group(registry, subject_3, GroupC)
}

//*---------------- members tests ---------------*//

pub fn can_retrieve_grouped_subjects_test() {
  let assert Ok(registry) = chip.start()
  let s1: process.Subject(Nil) = process.new_subject()
  let s2: process.Subject(Nil) = process.new_subject()
  let s3: process.Subject(Nil) = process.new_subject()
  let s4: process.Subject(Nil) = process.new_subject()
  let s5: process.Subject(Nil) = process.new_subject()
  let s6: process.Subject(Nil) = process.new_subject()

  // manually group all subjects
  chip.group(registry, s1, GroupA)
  chip.group(registry, s2, GroupB)
  chip.group(registry, s3, GroupB)
  chip.group(registry, s4, GroupC)
  chip.group(registry, s5, GroupC)
  chip.group(registry, s6, GroupC)

  // assert we can retrieve groups
  let assert [_] = chip.members(registry, GroupA)
  let assert [_, _] = chip.members(registry, GroupB)
  let assert [_, _, _] = chip.members(registry, GroupC)
}

pub fn retrieves_an_empty_list_with_unused_group_test() {
  let assert Ok(registry) = chip.start()

  let assert [] = chip.members(registry, GroupA)
}

//*---------------- broadcast tests --------------*//

pub fn broadcast_test() {
  let assert Ok(registry) = chip.start()
  let subject: process.Subject(Nil) = process.new_subject()
  let assert Nil = chip.group(registry, subject, 0)

  let assert Nil = chip.broadcast(registry, 0, fn(_subject) { Nil })
}

pub fn operations_are_applied_on_broadcast_test() {
  // start a new counter registry
  let assert Ok(registry) = chip.start()
  let registry: Registry = registry

  // actors being spawned
  let assert Ok(counter_1) = counter.start(1)
  let assert Ok(counter_2) = counter.start(2)
  let assert Ok(counter_3) = counter.start(3)

  //manually group all actors
  chip.group(registry, counter_1, GroupA)
  chip.group(registry, counter_2, GroupA)
  chip.group(registry, counter_3, GroupA)

  // assert that operations on group are succesful 
  let assert [a, b, c] = chip.members(registry, GroupA)
  let assert 6 = counter.current(a) + counter.current(b) + counter.current(c)

  chip.broadcast(registry, GroupA, fn(subject) { counter.increment(subject) })

  let assert [a, b, c] = chip.members(registry, GroupA)
  let assert 9 = counter.current(a) + counter.current(b) + counter.current(c)
}

//*---------------- other tests ------------------*//

pub fn subject_eventually_deregisters_after_process_dies_test() {
  let assert Ok(registry) = chip.start()
  let registry: Registry = registry

  // start a new counter registry
  let assert Ok(counter) = counter.start(0)
  chip.register(registry, counter, "counter")

  // stops the counter actor
  counter.stop(counter)

  // eventually the counter should be automatically de-registered
  let find = fn() { chip.find(registry, "counter") }
  let assert True = until(find, is: Error(Nil), for: 50)
}

pub fn subject_eventually_degroups_after_process_dies_test() {
  let assert Ok(registry) = chip.start()
  let registry: Registry = registry

  // start a new counter registry
  let assert Ok(counter) = counter.start(0)
  chip.group(registry, counter, GroupA)

  // stops the counter actor
  counter.stop(counter)

  // eventually the counter should be automatically de-registered
  let find = fn() { chip.members(registry, GroupA) }
  let assert True = until(find, is: [], for: 50)
}

pub fn registering_works_along_supervisor_test() {
  let assert Ok(registry) = chip.start()
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
  process.Subject(chip.Message(String, Group, counter.Message))

type Group {
  GroupA
  GroupB
  GroupC
}

fn child_spec(registry) {
  // an actor will be spawned and immediately registered after success
  let start = fn(id) {
    let initial_count = id
    let name = "counter-" <> int.to_string(id)

    use subject <- result.try(counter.start(initial_count))
    let Nil = chip.register(registry, subject, name)
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
