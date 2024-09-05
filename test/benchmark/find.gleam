type Scenario {
  Find
}

pub fn main() {
  run(Find)
}

@external(erlang, "Elixir.Chip.Benchmark", "run")
fn run(scenario: Scenario) -> x
