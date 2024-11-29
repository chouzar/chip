import artifacts/game.{DrawCard, FireDice, PlayChip}
import chip
import gleam/erlang/process
import gleam/otp/supervisor
import gleeunit

//*---------------- lookup tests -------------------*//

pub fn can_retrieve_all_registered_subjects_test() {
  let assert Ok(registry) = chip.start(chip.Unnamed)

  let assert Ok(session_1) = game.start(DrawCard)
  let assert Ok(session_2) = game.start(DrawCard)
  let assert Ok(session_3) = game.start(DrawCard)
  let assert Ok(session_4) = game.start(DrawCard)
  let assert Ok(session_5) = game.start(DrawCard)
  let assert Ok(session_6) = game.start(DrawCard)

  session_1 |> chip.register(registry, RoomA, _)
  session_2 |> chip.register(registry, RoomB, _)
  session_3 |> chip.register(registry, RoomB, _)
  session_4 |> chip.register(registry, RoomC, _)
  session_5 |> chip.register(registry, RoomC, _)
  session_6 |> chip.register(registry, RoomC, _)

  let assert [_] = chip.members(registry, RoomA, 50)
  let assert [_, _] = chip.members(registry, RoomB, 50)
  let assert [_, _, _] = chip.members(registry, RoomC, 50)
}

pub fn can_retrieve_different_subjects_of_same_process() {
  let assert Ok(registry) = chip.start(chip.Unnamed)

  process.new_subject() |> chip.register(registry, Nil, _)
  process.new_subject() |> chip.register(registry, Nil, _)
  process.new_subject() |> chip.register(registry, Nil, _)

  let assert [_, _, _] = chip.members(registry, Nil, 50)
}

pub fn cannot_retrieve_duplicate_subjects_test() {
  let assert Ok(registry) = chip.start(chip.Unnamed)

  let self = process.new_subject()

  self |> chip.register(registry, Nil, _)
  self |> chip.register(registry, Nil, _)
  self |> chip.register(registry, Nil, _)

  let assert [_] = chip.members(registry, Nil, 50)
}

//*---------------- dispatch tests --------------*//

pub fn dispatch_is_applied_over_subjects_test() {
  let assert Ok(registry) = chip.start(chip.Unnamed)

  let assert Ok(session_1) = game.start(DrawCard)
  let assert Ok(session_2) = game.start(PlayChip)
  let assert Ok(session_3) = game.start(PlayChip)
  let assert Ok(session_4) = game.start(FireDice)
  let assert Ok(session_5) = game.start(FireDice)
  let assert Ok(session_6) = game.start(FireDice)

  session_1 |> chip.register(registry, Nil, _)
  session_2 |> chip.register(registry, Nil, _)
  session_3 |> chip.register(registry, Nil, _)
  session_4 |> chip.register(registry, Nil, _)
  session_5 |> chip.register(registry, Nil, _)
  session_6 |> chip.register(registry, Nil, _)

  chip.dispatch(registry, Nil, game.next)

  // wait for game session operation to finish
  let assert True = until(fn() { game.current(session_1) }, is: "🪙", for: 50)
  let assert True = until(fn() { game.current(session_2) }, is: "🎲", for: 50)
  let assert True = until(fn() { game.current(session_3) }, is: "🎲", for: 50)
  let assert True = until(fn() { game.current(session_4) }, is: "🂡", for: 50)
  let assert True = until(fn() { game.current(session_5) }, is: "🂡", for: 50)
  let assert True = until(fn() { game.current(session_6) }, is: "🂡", for: 50)
}

pub fn dispatch_is_applied_over_groups_test() {
  let assert Ok(registry) = chip.start(chip.Unnamed)

  let assert Ok(session_1) = game.start(DrawCard)
  let assert Ok(session_2) = game.start(DrawCard)
  let assert Ok(session_3) = game.start(DrawCard)
  let assert Ok(session_4) = game.start(DrawCard)
  let assert Ok(session_5) = game.start(DrawCard)
  let assert Ok(session_6) = game.start(DrawCard)

  session_1 |> chip.register(registry, RoomA, _)
  session_2 |> chip.register(registry, RoomB, _)
  session_3 |> chip.register(registry, RoomB, _)
  session_4 |> chip.register(registry, RoomC, _)
  session_5 |> chip.register(registry, RoomC, _)
  session_6 |> chip.register(registry, RoomC, _)

  chip.dispatch(registry, RoomA, fn(subject) { game.next(subject) })

  chip.dispatch(registry, RoomB, fn(subject) {
    game.next(subject)
    game.next(subject)
  })

  chip.dispatch(registry, RoomC, fn(subject) {
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
  let assert Ok(registry) = chip.start(chip.Unnamed)

  let assert Ok(session) = game.start(DrawCard)
  chip.register(registry, "my-game", session)

  // stops the game session actor
  game.stop(session)

  // eventually the game session should be automatically de-registered
  let find = fn() { chip.members(registry, "my-game", 50) }
  let assert True = until(find, is: [], for: 50)
}

pub fn registering_works_along_supervisor_test() {
  let assert Ok(registry) = chip.start(chip.Unnamed)

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
  let assert [session_1] = chip.members(registry, 1, 50)
  let assert "🂡" = game.current(session_1)

  let assert [session_2] = chip.members(registry, 2, 50)
  let assert "🪙" = game.current(session_2)

  let assert [session_3] = chip.members(registry, 3, 50)
  let assert "🎲" = game.current(session_3)

  // assert we're not able to retrieve non-registered subjects
  let assert [] = chip.members(registry, 4, 50)

  // assert subject is restarted by the supervisor after actor dies
  game.stop(session_2)

  let different_subject = fn() {
    case chip.members(registry, 2, 50) {
      [session] if session != session_2 -> True
      _other -> False
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
