import gleeunit
import gleam/list
import gleam/erlang/process
import gleam/otp/actor
import chip

pub fn main() {
  gleeunit.main()
}

type Groups {
  GroupA
  GroupB
  GroupC
}

pub fn group_test() {
  let assert Ok(registry) = chip.start()

  let start_counter = fn(count) {
    chip.register(registry, fn() { start_counter(count) })
  }

  let assert [] = chip.all(registry)

  let assert Ok(counter_1) = start_counter(10)
  let assert Ok(counter_2) = start_counter(100)
  let assert Ok(counter_3) = start_counter(1000)

  let assert [_, _, _] = chip.all(registry)

  registry
  |> chip.all()
  |> list.each(process.send(_, Inc))

  let assert 11 = process.call(counter_1, Current(_), 10)
  let assert 101 = process.call(counter_2, Current(_), 10)
  let assert 1001 = process.call(counter_3, Current(_), 10)
}

pub fn named_group_test() {
  let assert Ok(registry) = chip.start()

  let start_counter = fn(name, count) {
    chip.register_as(registry, name, fn() { start_counter(count) })
  }

  let assert [] = chip.all(registry)

  let assert Ok(counter_1) = start_counter(GroupA, 10)
  let assert Ok(counter_2) = start_counter(GroupB, 100)
  let assert Ok(counter_3) = start_counter(GroupB, 1000)
  let assert Ok(counter_4) = start_counter(GroupC, 10_000)
  let assert Ok(counter_5) = start_counter(GroupC, 100_000)
  let assert Ok(counter_6) = start_counter(GroupC, 1_000_000)

  let assert [_, _, _, _, _, _] = chip.all(registry)
  let assert [_] = chip.lookup(registry, GroupA)
  let assert [_, _] = chip.lookup(registry, GroupB)
  let assert [_, _, _] = chip.lookup(registry, GroupC)

  registry
  |> chip.lookup(GroupB)
  |> list.each(process.send(_, Inc))

  registry
  |> chip.lookup(GroupC)
  |> list.each(fn(self) {
    process.send(self, Inc)
    process.send(self, Inc)
  })

  let assert 10 = process.call(counter_1, Current(_), 10)
  let assert 101 = process.call(counter_2, Current(_), 10)
  let assert 1001 = process.call(counter_3, Current(_), 10)
  let assert 10_002 = process.call(counter_4, Current(_), 10)
  let assert 100_002 = process.call(counter_5, Current(_), 10)
  let assert 1_000_002 = process.call(counter_6, Current(_), 10)
}

pub fn deregister_test() {
  // Start registry and register 5 counters
  let assert Ok(registry) = chip.start()

  let assert Ok(counter_1) = start_counter(10)
  let assert Ok(counter_2) = start_counter(100)
  let assert Ok(counter_3) = start_counter(1000)
  let assert Ok(counter_4) = start_counter(10_000)
  let assert Ok(counter_5) = start_counter(100_000)

  let _ = chip.register(registry, fn() { Ok(counter_1) })
  let _ = chip.register(registry, fn() { Ok(counter_2) })
  let _ = chip.register_as(registry, GroupA, fn() { Ok(counter_2) })
  let _ = chip.register_as(registry, GroupB, fn() { Ok(counter_2) })
  let _ = chip.register_as(registry, GroupB, fn() { Ok(counter_3) })
  let _ = chip.register_as(registry, GroupB, fn() { Ok(counter_4) })
  let _ = chip.register_as(registry, GroupC, fn() { Ok(counter_4) })
  let _ = chip.register(registry, fn() { Ok(counter_4) })
  let _ = chip.register(registry, fn() { Ok(counter_5) })

  // So far we have...
  let assert [_, _, _, _, _] = chip.all(registry)
  let assert [_] = chip.lookup(registry, GroupA)
  let assert [_, _, _] = chip.lookup(registry, GroupB)
  let assert [_] = chip.lookup(registry, GroupC)

  // Deregistering Group B removes counter 3 but not 2 or 4  
  chip.deregister(registry, GroupB)
  let assert [_, _, _, _] = chip.all(registry)
  let assert [_] = chip.lookup(registry, GroupA)
  let assert [] = chip.lookup(registry, GroupB)
  let assert [_] = chip.lookup(registry, GroupC)

  // Deregistering Group A removes counter 2
  chip.deregister(registry, GroupA)
  let assert [_, _, _] = chip.all(registry)
  let assert [_, _, _] = chip.all(registry)
  let assert [] = chip.lookup(registry, GroupA)
  let assert [] = chip.lookup(registry, GroupB)
  let assert [_] = chip.lookup(registry, GroupC)

  // Deregistering Group C removes counter 4
  chip.deregister(registry, GroupC)
  let assert [_, _] = chip.all(registry)
  let assert [] = chip.lookup(registry, GroupA)
  let assert [] = chip.lookup(registry, GroupB)
  let assert [] = chip.lookup(registry, GroupC)
}

pub fn demonitor_test() {
  // Start registry and register 5 counters
  let assert Ok(registry) = chip.start()

  let assert Ok(counter_1) = start_counter(10)
  let assert Ok(counter_2) = start_counter(100)
  let assert Ok(counter_3) = start_counter(1000)
  let assert Ok(counter_4) = start_counter(10_000)
  let assert Ok(counter_5) = start_counter(100_000)

  let _ = chip.register(registry, fn() { Ok(counter_1) })
  let _ = chip.register(registry, fn() { Ok(counter_2) })
  let _ = chip.register_as(registry, GroupA, fn() { Ok(counter_2) })
  let _ = chip.register_as(registry, GroupB, fn() { Ok(counter_2) })
  let _ = chip.register_as(registry, GroupB, fn() { Ok(counter_3) })
  let _ = chip.register_as(registry, GroupB, fn() { Ok(counter_4) })
  let _ = chip.register_as(registry, GroupC, fn() { Ok(counter_4) })
  let _ = chip.register(registry, fn() { Ok(counter_4) })
  let _ = chip.register(registry, fn() { Ok(counter_5) })

  // So far we have...
  let assert [_, _, _, _, _] = chip.all(registry)
  let assert [_] = chip.lookup(registry, GroupA)
  let assert [_, _, _] = chip.lookup(registry, GroupB)
  let assert [_] = chip.lookup(registry, GroupC)

  // Stopping counter 3 removes it from the group and B subgroup
  let assert 1000 = stop_counter(counter_3)
  let assert [_, _, _, _] = chip.all(registry)
  let assert [_] = chip.lookup(registry, GroupA)
  let assert [_, _] = chip.lookup(registry, GroupB)
  let assert [_] = chip.lookup(registry, GroupC)

  // Stopping counter 2 removes it from the group and A, B subgroup 
  let assert 100 = stop_counter(counter_2)
  let assert [_, _, _] = chip.all(registry)
  let assert [] = chip.lookup(registry, GroupA)
  let assert [_] = chip.lookup(registry, GroupB)
  let assert [_] = chip.lookup(registry, GroupC)

  // Stopping counter 4 removes it from the group and B, C subgroup
  let assert 10_000 = stop_counter(counter_4)
  let assert [_, _] = chip.all(registry)
  let assert [] = chip.lookup(registry, GroupA)
  let assert [] = chip.lookup(registry, GroupB)
  let assert [] = chip.lookup(registry, GroupC)
}

pub fn stop_test() {
  let assert Ok(registry) = chip.start()
  let assert process.Normal = chip.stop(registry)
  let assert False =
    registry
    |> process.subject_owner()
    |> process.is_alive()
}

pub opaque type CounterMessage {
  Inc
  Current(client: process.Subject(Int))
  Stop(client: process.Subject(Int))
}

fn start_counter(count: Int) {
  actor.start(count, handle_count)
}

fn stop_counter(counter: process.Subject(CounterMessage)) -> Int {
  actor.call(counter, Stop(_), 10)
}

fn handle_count(message: CounterMessage, count: Int) {
  case message {
    Inc -> {
      actor.continue(count + 1)
    }

    Current(client) -> {
      process.send(client, count)
      actor.continue(count)
    }

    Stop(client) -> {
      process.send(client, count)
      actor.Stop(process.Normal)
    }
  }
}
