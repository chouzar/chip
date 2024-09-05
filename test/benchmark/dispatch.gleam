type Scenario {
  Dispatch
}

pub fn main() {
  run(Dispatch)
}

@external(erlang, "Elixir.Chip.Benchmark", "run")
fn run(scenario: Scenario) -> x
