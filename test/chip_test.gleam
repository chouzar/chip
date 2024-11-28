import artifacts/game.{DrawCard, FireDice, PlayChip}
import chip
import gleam/erlang/process
import gleam/otp/supervisor
import gleeunit

//*---------------- lookup tests -------------------*//

pub fn can_retrieve_individual_subjects_test() {
  let assert Ok(registry) = chip.start()

  let self: process.Subject(Nil) = process.new_subject()

  chip.new(self) |> chip.tag(1) |> chip.register(registry, _)
  chip.new(self) |> chip.tag(2) |> chip.register(registry, _)
  chip.new(self) |> chip.tag(3) |> chip.register(registry, _)

  let assert Ok(_subject) = chip.find(registry, 1)
  let assert Ok(_subject) = chip.find(registry, 2)
  let assert Ok(_subject) = chip.find(registry, 3)
}

pub fn cannot_retrieve_subject_if_not_registered_test() {
  let assert Ok(registry) = chip.start()

  let assert Error(Nil) = chip.find(registry, "nothing")
}

//*---------------- all tests --------------*//

pub fn can_retrieve_all_registered_subjects_test() {
  todo
}

pub fn can_retrieve_different_subjects_of_same_process() {
  todo
}

pub fn cannot_retrieve_duplicate_subjects_test() {
  todo
}

//*---------------- dispatch tests --------------*//

pub fn dispatch_is_applied_over_subjects_test() {
  let assert Ok(registry) = chip.start()

  let assert Ok(session_1) = game.start(DrawCard)
  let assert Ok(session_2) = game.start(PlayChip)
  let assert Ok(session_3) = game.start(PlayChip)
  let assert Ok(session_4) = game.start(FireDice)
  let assert Ok(session_5) = game.start(FireDice)
  let assert Ok(session_6) = game.start(FireDice)

  chip.new(session_1) |> chip.register(registry, _)
  chip.new(session_2) |> chip.register(registry, _)
  chip.new(session_3) |> chip.register(registry, _)
  chip.new(session_4) |> chip.register(registry, _)
  chip.new(session_5) |> chip.register(registry, _)
  chip.new(session_6) |> chip.register(registry, _)

  chip.dispatch(registry, game.next)

  // wait for game session operation to finish
  let assert True = until(fn() { game.current(session_1) }, is: "🪙", for: 50)
  let assert True = until(fn() { game.current(session_2) }, is: "🎲", for: 50)
  let assert True = until(fn() { game.current(session_3) }, is: "🎲", for: 50)
  let assert True = until(fn() { game.current(session_4) }, is: "🂡", for: 50)
  let assert True = until(fn() { game.current(session_5) }, is: "🂡", for: 50)
  let assert True = until(fn() { game.current(session_6) }, is: "🂡", for: 50)
}

pub fn dispatch_is_applied_over_groups_test() {
  let assert Ok(registry) = chip.start()

  let assert Ok(session_1) = game.start(DrawCard)
  let assert Ok(session_2) = game.start(DrawCard)
  let assert Ok(session_3) = game.start(DrawCard)
  let assert Ok(session_4) = game.start(DrawCard)
  let assert Ok(session_5) = game.start(DrawCard)
  let assert Ok(session_6) = game.start(DrawCard)

  chip.new(session_1) |> chip.group(RoomA) |> chip.register(registry, _)
  chip.new(session_2) |> chip.group(RoomB) |> chip.register(registry, _)
  chip.new(session_3) |> chip.group(RoomB) |> chip.register(registry, _)
  chip.new(session_4) |> chip.group(RoomC) |> chip.register(registry, _)
  chip.new(session_5) |> chip.group(RoomC) |> chip.register(registry, _)
  chip.new(session_6) |> chip.group(RoomC) |> chip.register(registry, _)

  chip.dispatch_group(registry, RoomA, fn(subject) { game.next(subject) })

  chip.dispatch_group(registry, RoomB, fn(subject) {
    game.next(subject)
    game.next(subject)
  })

  chip.dispatch_group(registry, RoomC, fn(subject) {
    game.next(subject)
    game.next(subject)
    game.next(subject)
  })

  // wait for game session operation to finish
  let assert True = until(fn() { game.current(session_1) }, is: "🪙", for: 50)
  let assert True = until(fn() { game.current(session_2) }, is: "🎲", for: 50)
  let assert True = until(fn() { game.current(session_3) }, is: "🎲", for: 50)
  let assert True = until(fn() { game.current(session_4) }, is: "🂡", for: 50)
  let assert True = until(fn() { game.current(session_5) }, is: "🂡", for: 50)
  let assert True = until(fn() { game.current(session_6) }, is: "🂡", for: 50)
}

//*---------------- other tests ------------------*//

pub fn subject_eventually_deregisters_after_process_dies_test() {
  let assert Ok(registry) = chip.start()

  let assert Ok(session) = game.start(DrawCard)
  chip.new(session) |> chip.tag("my-game") |> chip.register(registry, _)

  // stops the game session actor
  game.stop(session)

  // eventually the game session should be automatically de-registered
  let find = fn() { chip.find(registry, "my-game") }
  let assert True = until(find, is: Error(Nil), for: 50)
}

pub fn registering_works_along_supervisor_test() {
  let assert Ok(registry) = chip.start()

  let assert Ok(_supervisor) =
    supervisor.start_spec(
      supervisor.Spec(
        argument: 1,
        max_frequency: 5,
        frequency_period: 1,
        init: fn(children) {
          children
          |> supervisor.add(game.childspec(registry, DrawCard))
          |> supervisor.add(game.childspec(registry, PlayChip))
          |> supervisor.add(game.childspec(registry, FireDice))
        },
      ),
    )

  // assert we can retrieve individual subjects
  let assert Ok(session_1) = chip.find(registry, 1)
  let assert "🂡" = game.current(session_1)

  let assert Ok(session_2) = chip.find(registry, 2)
  let assert "🪙" = game.current(session_2)

  let assert Ok(session_3) = chip.find(registry, 3)
  let assert "🎲" = game.current(session_3)

  // assert we're not able to retrieve non-registered subjects
  let assert Error(Nil) = chip.find(registry, 4)

  // assert subject is restarted by the supervisor after actor dies
  game.stop(session_2)

  let different_subject = fn() {
    case chip.find(registry, 2) {
      Ok(session) if session != session_2 -> True
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

type Room {
  RoomA
  RoomB
  RoomC
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
