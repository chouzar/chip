type Scenario {
  Find
  Dispatch
  DispatchGroup
}

pub fn main() {
  performance(Find)
  performance(Dispatch)
  performance(DispatchGroup)
  memory()
}

@external(erlang, "Elixir.Chip.Benchmark.Performance", "run")
fn performance(scenario: Scenario) -> x

@external(erlang, "Elixir.Chip.Benchmark.Memory", "run")
fn memory() -> x
