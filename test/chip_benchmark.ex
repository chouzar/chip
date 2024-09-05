defmodule Chip.Benchmark do
  # TODO: Between benchmarks try to print he memory foot print.
  #   * Memory footprint can be measured for the process itself

  @clock :benchmark@clock
  @chip :chip
  @process :gleam@erlang@process

  def run(scenario) do
    inputs = %{
      "10 clocks" => 1..10,
      "100 clocks" => 1..100,
      "1000 clocks" => 1..1_000,
      "10000 clocks" => 1..10_000,
      "100000 clocks" => 1..100_000,
      "f 1000000 set" => 1..1_000_000,
      "g 10000000 set" => 1..10_000_000
    }

    before_senario = fn set ->
      {:ok, registry} = @chip.start()

      for id <- set do
        group = Enum.random([:group_a, :group_b, :group_c])
        @clock.start(registry, id, group, 0)
      end

      {registry, set}
    end

    before_each = fn {registry, set} ->
      {registry, Enum.random(set), Enum.random([:group_a, :group_b, :group_c])}
    end

    after_scenario = fn {registry, _set} ->
      IO.puts("\n--- Rough memory measurements ---\n")
      size = unit_measurement()
      IO.puts("   Unit of measurement: #{size}")

      %{monitors: monitors, memory: memory_before} =
        subject_info(registry)

      IO.puts("   Monitors: #{Enum.count(monitors)}")
      IO.puts("   Current memory: #{memory_before}")

      @chip.dispatch(registry, fn subject ->
        @clock.stop(subject)
      end)

      IO.puts("   Deregistering subjects from Registry...")
      :ok = wait_demonitor(registry)

      %{monitors: monitors, memory: memory_after} =
        subject_info(registry)

      IO.puts("   Monitors: #{Enum.count(monitors)}")

      IO.puts(
        "   Liberated memory: #{memory_before} - #{memory_after} = #{memory_before - memory_after}\n"
      )

      :chip.stop(registry)

      nil
    end

    scenario =
      case scenario do
        :find ->
          %{
            "chip.find" => fn {registry, id, _group} ->
              {:ok, _} = @chip.find(registry, id)
            end
          }

        :dispatch ->
          %{
            "chip.dispatch" => fn {registry, _id, _group} ->
              @chip.dispatch(registry, fn subject ->
                @clock.increment(subject)
              end)
            end
          }

        :dispatch_group ->
          %{
            "chip.dispatch_group" => fn {registry, _id, group} ->
              @chip.dispatch_group(registry, group, fn subject ->
                @clock.increment(subject)
              end)
            end
          }
      end

    Benchee.run(scenario,
      inputs: inputs,
      before_scenario: before_senario,
      before_each: before_each,
      after_scenario: after_scenario,
      time: 3,
      print: %{configuration: false}
    )

    IO.puts("----------------------------------- THE END -----------------------------------n")
  end

  # https://www.erlang.org/doc/system/profiling.html#never-guess-about-performance-bottlenecks
  # https://www.erlang.org/doc/system/profiling.html#memory-profiling
  # https://www.erlang.org/doc/apps/erts/erlang#process_info/2

  defp subject_info(subject) do
    pid = @process.subject_owner(subject)

    [{:monitors, monitors}, {:memory, memory}] =
      :erlang.process_info(pid, [
        :monitors,
        :memory
      ])

    %{monitors: monitors, memory: memory}
  end

  defp unit_measurement() do
    :erlang.system_info(:wordsize)
  end

  defp wait_demonitor(subject) do
    case subject_info(subject) do
      %{monitors: []} ->
        :ok

      %{monitors: _monitors} ->
        Process.sleep(200)
        wait_demonitor(subject)
    end
  end
end
