import gleeunit
import gleam/list
import gleam/erlang/process
import gleam/otp/actor
import chip

pub fn main() {
  gleeunit.main()
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

type Counters {
  CounterA
  CounterB
  CounterC
}

pub fn named_group_test() {
  let assert Ok(registry) = chip.start()

  let start_counter = fn(name, count) {
    chip.register_as(registry, name, fn() { start_counter(count) })
  }

  let assert [] = chip.all(registry)

  let assert Ok(counter_1) = start_counter(CounterA, 10)
  let assert Ok(counter_2) = start_counter(CounterB, 100)
  let assert Ok(counter_3) = start_counter(CounterB, 1000)
  let assert Ok(counter_4) = start_counter(CounterC, 10_000)
  let assert Ok(counter_5) = start_counter(CounterC, 100_000)
  let assert Ok(counter_6) = start_counter(CounterC, 1_000_000)

  let assert [_, _, _, _, _, _] = chip.all(registry)
  let assert [_] = chip.lookup(registry, CounterA)
  let assert [_, _] = chip.lookup(registry, CounterB)
  let assert [_, _, _] = chip.lookup(registry, CounterC)

  registry
  |> chip.lookup(CounterB)
  |> list.each(process.send(_, Inc))

  registry
  |> chip.lookup(CounterC)
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

  chip.deregister(registry, CounterC)
  let assert [_, _, _] = chip.all(registry)
  let assert [] = chip.lookup(registry, CounterC)

  chip.deregister(registry, CounterB)
  let assert [_] = chip.all(registry)
  let assert [] = chip.lookup(registry, CounterB)
}

pub fn deregister_test() {
  let assert Ok(registry) = chip.start()

  let assert [] = chip.all(registry)

  let assert Ok(counter_1) = start_counter(10)
  let assert Ok(counter_2) = start_counter(100)
  let assert Ok(counter_3) = start_counter(1000)

  let _ = chip.register(registry, fn() { Ok(counter_1) })
  let _ = chip.register_as(registry, CounterB, fn() { Ok(counter_1) })

  let _ = chip.register_as(registry, CounterA, fn() { Ok(counter_2) })
  let _ = chip.register_as(registry, CounterB, fn() { Ok(counter_2) })
  let _ = chip.register_as(registry, CounterC, fn() { Ok(counter_2) })

  let _ = chip.register_as(registry, CounterB, fn() { Ok(counter_3) })
  let _ = chip.register_as(registry, CounterB, fn() { Ok(counter_3) })
  let _ = chip.register_as(registry, CounterB, fn() { Ok(counter_3) })

  let assert [_, _, _] = chip.all(registry)
  let assert [_] = chip.lookup(registry, CounterA)
  let assert [_, _, _] = chip.lookup(registry, CounterB)
  let assert [_] = chip.lookup(registry, CounterC)

  chip.deregister(registry, CounterA)
  let assert [_, _, _] = chip.all(registry)
  let assert [] = chip.lookup(registry, CounterA)

  chip.deregister(registry, CounterB)
  let assert [counter_2] = chip.all(registry)
  let assert [] = chip.lookup(registry, CounterB)
  let assert 100 = process.call(counter_2, Current(_), 10)

  chip.deregister(registry, CounterC)
  let assert [] = chip.all(registry)
  let assert [] = chip.lookup(registry, CounterC)
}

pub fn stop_test() {
  let assert Ok(registry) = chip.start()
  let assert Ok(Nil) = chip.stop(registry)
  let assert False =
    registry
    |> process.subject_owner()
    |> process.is_alive()
}

pub fn delist_dead_process_test() {
  todo
}

pub opaque type CounterMessage {
  Inc
  Current(client: process.Subject(Int))
  Stop(client: process.Subject(Result(Nil, Nil)))
}

fn start_counter(count: Int) {
  actor.start(count, handle_count)
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
      process.send(client, Ok(Nil))
      actor.Stop(process.Normal)
    }
  }
}
