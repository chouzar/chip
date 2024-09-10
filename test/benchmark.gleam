type Scenario {
  Find
  Dispatch
  DispatchGroup
}

pub fn main() {
  run(Find)
  run(Dispatch)
  run(DispatchGroup)
}

@external(erlang, "Elixir.Chip.Benchmark.Performance", "run")
fn run(scenario: Scenario) -> x
