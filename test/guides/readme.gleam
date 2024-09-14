import artifacts/game.{DrawCard, FireDice, PlayChip}
import chip

pub fn main() {
  let assert Ok(registry) = chip.start()

  let assert Ok(session_a) = game.start(DrawCard)
  let assert Ok(session_b) = game.start(FireDice)
  let assert Ok(session_c) = game.start(PlayChip)

  chip.register(registry, chip.new(session_a))
  chip.register(registry, chip.new(session_b))
  chip.register(registry, chip.new(session_c))

  chip.dispatch(registry, fn(session) { game.next(session) })
}
