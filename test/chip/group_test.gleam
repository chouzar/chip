import chip/group
import counter
import gleam/erlang/process
import gleeunit

//*---------------- start tests -===---------------*//

pub fn can_start_registry_test() {
  let assert Ok(_registry) = group.start()
}

//*---------------- group tests -----------------*//

pub fn can_group_subjects_test() {
  let assert Ok(registry) = group.start()
  let subject_1: process.Subject(Nil) = process.new_subject()
  let subject_2: process.Subject(Nil) = process.new_subject()
  let subject_3: process.Subject(Nil) = process.new_subject()

  let assert Nil = group.register(registry, subject_1, GroupA)
  let assert Nil = group.register(registry, subject_2, GroupB)
  let assert Nil = group.register(registry, subject_3, GroupC)
}

//*---------------- members tests ---------------*//

pub fn can_retrieve_grouped_subjects_test() {
  let assert Ok(registry) = group.start()
  let s1: process.Subject(Nil) = process.new_subject()
  let s2: process.Subject(Nil) = process.new_subject()
  let s3: process.Subject(Nil) = process.new_subject()
  let s4: process.Subject(Nil) = process.new_subject()
  let s5: process.Subject(Nil) = process.new_subject()
  let s6: process.Subject(Nil) = process.new_subject()

  // manually group all subjects
  group.register(registry, s1, GroupA)
  group.register(registry, s2, GroupB)
  group.register(registry, s3, GroupB)
  group.register(registry, s4, GroupC)
  group.register(registry, s5, GroupC)
  group.register(registry, s6, GroupC)

  // assert we can retrieve groups
  let assert [_] = group.members(registry, GroupA)
  let assert [_, _] = group.members(registry, GroupB)
  let assert [_, _, _] = group.members(registry, GroupC)
}

pub fn retrieves_an_empty_list_with_unused_group_test() {
  let assert Ok(registry) = group.start()

  let assert [] = group.members(registry, GroupA)
}

//*---------------- dispatch tests --------------*//

pub fn dispatch_test() {
  let assert Ok(registry) = group.start()
  let subject: process.Subject(Nil) = process.new_subject()
  let assert Nil = group.register(registry, subject, 0)

  let assert Nil = group.dispatch(registry, 0, fn(_subject) { Nil })
}

pub fn operations_are_applied_on_dispatch_test() {
  // start a new counter registry
  let assert Ok(registry) = group.start()
  let registry: Registry = registry

  // actors being spawned
  let assert Ok(counter_1) = counter.start(1)
  let assert Ok(counter_2) = counter.start(2)
  let assert Ok(counter_3) = counter.start(3)

  //manually group all actors
  group.register(registry, counter_1, GroupA)
  group.register(registry, counter_2, GroupA)
  group.register(registry, counter_3, GroupA)

  // assert that operations on group are succesful 
  let assert [a, b, c] = group.members(registry, GroupA)
  let assert 6 = counter.current(a) + counter.current(b) + counter.current(c)

  group.dispatch(registry, GroupA, fn(subject) { counter.increment(subject) })

  let assert [a, b, c] = group.members(registry, GroupA)
  let assert 9 = counter.current(a) + counter.current(b) + counter.current(c)
}

//*---------------- other tests ------------------*//

pub fn subject_eventually_degroups_after_process_dies_test() {
  let assert Ok(registry) = group.start()
  let registry: Registry = registry

  // start a new counter registry
  let assert Ok(counter) = counter.start(0)
  group.register(registry, counter, GroupA)

  // stops the counter actor
  counter.stop(counter)

  // eventually the counter should be automatically de-registered
  let find = fn() { group.members(registry, GroupA) }
  let assert True = until(find, is: [], for: 50)
}

//*---------------- Test helpers ----------------*//

pub fn main() {
  gleeunit.main()
}

type Registry =
  process.Subject(group.Message(Group, counter.Message))

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
