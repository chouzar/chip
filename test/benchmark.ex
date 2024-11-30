defmodule Chip.Benchmark.Performance do
  @clock :artifacts@clock
  @chip :chip
  @process :gleam@erlang@process

  def run(scenario) do
    # inputs =
    #   %{
    #     "10 clocks" => 1..10,
    #     "100 clocks" => 1..100,
    #     "1000 clocks" => 1..1_000,
    #     "10000 clocks" => 1..10_000,
    #     "100000 clocks" => 1..100_000,
    #     "1000000 clocks" => 1..1_000_000,
    #     "10000000 clocks" => 1..10_000_000
    #   }

    scenario =
      case scenario do
        :members ->
          %{
            "a chip.members, retrieve 10" => {
              fn {registry, id, _group} -> @chip.members(registry, id, 5000) end,
              before_scenario: fn _set -> before_scenario(1..10) end,
              before_each: fn {registry, set} -> before_each(registry, set) end,
              after_scenario: fn {registry, _set} -> after_scenario(registry) end
            },
            "b chip.members, retrieve 100" => {
              fn {registry, id, _group} -> @chip.members(registry, id, 5000) end,
              before_scenario: fn _set -> before_scenario(1..100) end,
              before_each: fn {registry, set} -> before_each(registry, set) end,
              after_scenario: fn {registry, _set} -> after_scenario(registry) end
            },
            "c chip.members, retrieve 1000" => {
              fn {registry, id, _group} -> @chip.members(registry, id, 5000) end,
              before_scenario: fn _set -> before_scenario(1..1000) end,
              before_each: fn {registry, set} -> before_each(registry, set) end,
              after_scenario: fn {registry, _set} -> after_scenario(registry) end
            },
            "d chip.members, retrieve 10000" => {
              fn {registry, id, _group} -> @chip.members(registry, id, 10_000) end,
              before_scenario: fn _set -> before_scenario(1..10000) end,
              before_each: fn {registry, set} -> before_each(registry, set) end,
              after_scenario: fn {registry, _set} -> after_scenario(registry) end
            }
          }
      end

    Benchee.run(scenario,
      # inputs: inputs,
      # before_scenario: fn set -> before_scenario(@chip, set) end,
      # before_each: fn {registry, set} -> before_each(registry, set) end,
      # after_scenario: fn {registry, _set} -> after_scenario(@chip, registry) end,
      time: 10,
      print: %{configuration: false}
    )
  end

  defp before_scenario(set) do
    {:ok, registry} = @chip.start(:unnamed)

    for id <- set do
      group = Enum.random([:group_a, :group_b, :group_c])
      @clock.start(registry, group, 0)

      if Integer.mod(id, 5000) == 0 do
        :ok = wait_for_clear_message_queue(registry)
      end
    end

    {registry, set}
  end

  defp before_each(registry, set) do
    {registry, Enum.random(set), Enum.random([:group_a, :group_b, :group_c])}
  end

  defp after_scenario(registry) do
    @chip.stop(registry)
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

defmodule Chip.Benchmark.Memory do
  @clock :artifacts@clock
  @chip :chip
  @process :gleam@erlang@process

  def run() do
    set = 1..10_000

    IO.puts("\n---------------------------------- THE START ----------------------------------\n")
    size = unit_measurement()
    IO.puts("   Unit of measurement: #{size}")

    {:ok, registry} = @chip.start(:unnamed)

    IO.puts("\n--- Rough memory measurements ---\n")

    IO.puts("   Before registration...")
    IO.puts("     self:")
    process_info(self()) |> display_info()
    IO.puts("     registry:")
    subject_info(registry) |> display_info()

    for id <- set do
      group = Enum.random([:group_a, :group_b, :group_c])
      @clock.start(registry, group, 0)

      if Integer.mod(id, 5000) == 0 do
        :ok = wait_for_clear_message_queue(registry)
      end
    end

    IO.puts("   After registration...")
    IO.puts("     self:")
    process_info(self()) |> display_info()
    IO.puts("     registry:")
    subject_info(registry) |> display_info()

    for id <- set do
      @chip.members(registry, :group_a, 5000)
      |> Enum.each(&@clock.stop(&1))

      @chip.members(registry, :group_b, 5000)
      |> Enum.each(&@clock.stop(&1))

      @chip.members(registry, :group_c, 5000)
      |> Enum.each(&@clock.stop(&1))

      if Integer.mod(id, 5000) == 0 do
        :ok = wait_demonitor(registry)
      end
    end

    IO.puts("   After demonitoring...")
    IO.puts("     self:")
    process_info(self()) |> display_info()
    IO.puts("     registry:")
    subject_info(registry) |> display_info()

    IO.puts("\n----------------------------------- THE END -----------------------------------\n")
  end

  # https://www.erlang.org/doc/system/profiling.html#never-guess-about-performance-bottlenecks
  # https://www.erlang.org/doc/system/profiling.html#memory-profiling
  # https://www.erlang.org/doc/apps/erts/erlang#process_info/2

  defp unit_measurement() do
    :erlang.system_info(:wordsize)
  end

  defp display_info(data) do
    %{monitors: monitors, memory: memory, message_queue_length: queue_length} =
      data

    IO.puts("       - mailbox: #{queue_length}")
    IO.puts("       - monitors: #{monitors}")
    IO.puts("       - memory: #{memory}")
    IO.puts("")
  end

  defp subject_info(subject) do
    pid = @process.subject_owner(subject)
    process_info(pid)
  end

  defp process_info(pid) do
    [{:monitors, monitors}, {:memory, memory}, {:message_queue_len, length}] =
      :erlang.process_info(pid, [
        :monitors,
        :memory,
        :message_queue_len
      ])

    %{monitors: Enum.count(monitors), memory: memory, message_queue_length: length}
  end

  defp wait_for_clear_message_queue(subject) do
    case subject_info(subject) do
      %{message_queue_length: 0} ->
        :ok

      %{message_queue_length: _length} ->
        Process.sleep(5000)
        wait_for_clear_message_queue(subject)
    end
  end

  defp wait_demonitor(subject) do
    case subject_info(subject) do
      %{monitors: 0} ->
        :ok

      %{monitors: _monitors} ->
        Process.sleep(5000)
        wait_demonitor(subject)
    end
  end
end
