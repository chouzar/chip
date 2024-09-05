defmodule Chip.Benchmark do
  # TODO: Between benchmarks try to print he memory foot print.
  #   * Memory footprint can be measured for the process itself

  @clock :benchmark@clock
  @chip :chip

  def main() do
    {:ok, registry} = @chip.start()

    inputs = %{
      "a 10 set" => 1..10,
      "b 100 set" => 1..100,
      "c 1000 set" => 1..1_000,
      "d 10000 set" => 1..10_000,
      #"e 100000 set" => 1..100_000,
      #"f 1000000 set" => 1..1_000_000,
      #"g 10000000 set" => 1..10_000_000
    }

    before_senario = fn set ->
      for id <- set do
        group = Enum.random([:group_a, :group_b, :group_c])
        @clock.start(registry, id, group, 0)
      end

      set
    end

    before_each = fn set ->
      {Enum.random(set), Enum.random([:group_a, :group_b, :group_c])}
    end

    after_scenario = fn _random_id ->
      @chip.dispatch(registry, fn subject ->
        @clock.stop(subject)
      end)
    end

    scenarios =
      %{
        "chip.find" => fn {id, _group} ->
          {:ok, _} = @chip.find(registry, id)
        end,
        "chip.dispatch" => fn {_id, _group} ->
          @chip.dispatch(registry, fn subject ->
            @clock.increment(subject)
          end)
        end,
        "chip.dispatch_group" => fn {_id, group} ->
          @chip.dispatch_group(registry, group, fn subject ->
            @clock.increment(subject)
          end)
        end
      }

    Benchee.run(scenarios,
      inputs: inputs,
      before_scenario: before_senario,
      before_each: before_each,
      after_scenario: after_scenario,
      time: 5
    )

    :chip.stop(registry)
  end
end
