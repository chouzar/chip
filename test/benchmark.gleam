type Scenario {
  Members
}

pub fn main() {
  performance(Members)
  memory()
}

@external(erlang, "Elixir.Chip.Benchmark.Performance", "run")
fn performance(scenario: Scenario) -> x

@external(erlang, "Elixir.Chip.Benchmark.Memory", "run")
fn memory() -> x
