import artifacts/spec
import chip
import gleam/erlang/process
import gleam/list
import gleam/otp/supervisor

pub fn main() {
  let self = process.new_subject()

  let assert Ok(_supervisor) =
    supervisor.start_spec(
      supervisor.Spec(
        argument: self,
        max_frequency: 5,
        frequency_period: 1,
        init: fn(children) {
          children
          // First spawn the registry
          |> supervisor.add(spec.registry())
          // Then spawn 1 to 50 game sessions
          |> list.fold(
            list.range(1, 50),
            _,
            fn(children, _id) { supervisor.add(children, spec.game()) },
          )
          // Finally notify the main process we're ready
          |> supervisor.add(spec.ready())
        },
      ),
    )

  let assert Ok(registry) = process.receive(self, 500)
  let assert [_session] = chip.members(registry, 33, 50)
}
