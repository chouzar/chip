type Scenario {
  DispatchGroup
}

pub fn main() {
  run(DispatchGroup)
}

@external(erlang, "Elixir.Chip.Benchmark", "run")
fn run(scenario: Scenario) -> x
