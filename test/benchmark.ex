defmodule Chip.Benchmark.Performance do
  @clock :benchmark@clock
  @chip :chip
  @chip_ets :chip_ets
  @process :gleam@erlang@process

  def run(scenario) do
    inputs = %{
      "10 clocks" => 1..10,
      "100 clocks" => 1..100
      # "1000 clocks" => 1..1_000,
      # "10000 clocks" => 1..10_000
      # "100000 clocks" => 1..100_000,
      # "1000000 clocks" => 1..1_000_000,
      # "10000000 clocks" => 1..10_000_000
    }

    scenario =
      case scenario do
        :find ->
          %{
            "chip.find" => fn {registry, id, _group} -> @chip.find(registry, id) end
          }

        :dispatch ->
          %{
            "chip.dispatch" => fn {registry, _id, _group} ->
              @chip.dispatch(registry, fn subject -> @clock.increment(subject) end)
            end
          }

        :dispatch_group ->
          %{
            "chip.dispatch_group" => fn {registry, _id, group} ->
              @chip.dispatch_group(registry, group, fn subject -> @clock.increment(subject) end)
            end
          }
      end

    Benchee.run(scenario,
      inputs: inputs,
      before_scenario: fn set -> before_scenario(@chip, set) end,
      before_each: fn {registry, set} -> before_each(registry, set) end,
      after_scenario: fn {registry, _set} -> after_scenario(@chip, registry) end,
      time: 3,
      print: %{configuration: false}
    )
  end

  defp before_scenario(module, set) do
    {:ok, registry} = module.start()

    for id <- set do
      group = Enum.random([:group_a, :group_b, :group_c])
      @clock.start(registry, id, group, 0)
    end

    :ok = wait_for_clear_message_queue(registry)

    {registry, set}
  end

  defp before_each(registry, set) do
    {registry, Enum.random(set), Enum.random([:group_a, :group_b, :group_c])}
  end

  defp after_scenario(module, registry) do
    module.stop(registry)
    IO.puts("")
    nil
  end

  # https://www.erlang.org/doc/system/profiling.html#never-guess-about-performance-bottlenecks
  # https://www.erlang.org/doc/system/profiling.html#memory-profiling
  # https://www.erlang.org/doc/apps/erts/erlang#process_info/2

  defp wait_for_clear_message_queue(subject) do
    case subject_info(subject) do
      %{message_queue_length: 0} ->
        :ok

      %{message_queue_length: _length, monitors: _monitors} ->
        Process.sleep(5000)
        wait_for_clear_message_queue(subject)
    end
  end

  defp subject_info(subject) do
    pid = @process.subject_owner(subject)

    [{:monitors, monitors}, {:memory, memory}, {:message_queue_len, length}] =
      :erlang.process_info(pid, [
        :monitors,
        :memory,
        :message_queue_len
      ])

    %{monitors: monitors, memory: memory, message_queue_length: length}
  end
end
