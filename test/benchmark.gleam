// https://www.erlang.org/doc/system/profiling.html#never-guess-about-performance-bottlenecks
// https://www.erlang.org/doc/system/profiling.html#memory-profiling
// https://www.erlang.org/doc/apps/erts/erlang#process_info/2

pub fn main() {
  run_benchmark()
  run_memory_benchmark()
}

@external(erlang, "Elixir.Chip.Benchmark", "run_benchmark")
fn run_benchmark() -> x

@external(erlang, "Elixir.Chip.Benchmark.Memory", "run_benchmark")
fn run_memory_benchmark() -> x
