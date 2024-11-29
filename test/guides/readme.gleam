import artifacts/game.{DrawCard, FireDice, PlayChip}
import chip

pub type Group {
  GroupA
  GroupB
}

pub fn main() {
  let assert Ok(registry) = chip.start(chip.Unnamed)

  let assert Ok(session_a) = game.start(DrawCard)
  let assert Ok(session_b) = game.start(FireDice)
  let assert Ok(session_c) = game.start(PlayChip)

  chip.register(registry, GroupA, session_a)
  chip.register(registry, GroupB, session_b)
  chip.register(registry, GroupA, session_c)

  chip.dispatch(registry, GroupA, fn(session) { game.next(session) })
}
