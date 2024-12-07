defmodule Chip.Benchmark.Performance do
  @clock :artifacts@clock
  @chip :chip
  @process :gleam@erlang@process

  def run(_scenario) do
    inputs = %{"10" => 10, "100" => 100, "1000" => 1000, "10000" => 10_000}

    Benchee.run(
      %{
        "chip.members" => fn {registry, id, _group} -> @chip.members(registry, id, 100) end
      },
      inputs: inputs,
      before_scenario: fn set -> before_scenario(1..set) end,
      before_each: fn {registry, set} -> before_each(registry, set) end,
      after_scenario: fn {registry, _set} -> after_scenario(registry) end,
      time: 5,
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
    # IO.puts("     self:")
    # process_info(self()) |> display_info()
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
    # IO.puts("     self:")
    # process_info(self()) |> display_info()
    IO.puts("     registry:")
    subject_info(registry) |> display_info()

    # @chip.members(registry, :group_a, 5000)
    # |> Enum.each(fn clock ->
    #   @clock.stop(clock)
    #   :ok = wait_for_clear_message_queue(registry)
    # end)

    # @chip.members(registry, :group_b, 25000)
    # |> Enum.each(fn clock ->
    #   @clock.stop(clock)
    #   :ok = wait_for_clear_message_queue(registry)
    # end)

    # @chip.members(registry, :group_c, 35000)
    # |> Enum.each(fn clock ->
    #   @clock.stop(clock)
    #   :ok = wait_for_clear_message_queue(registry)
    # end)

    # :ok = wait_demonitor(registry)

    # IO.puts("   After demonitoring...")
    # IO.puts("     self:")
    # process_info(self()) |> display_info()
    # IO.puts("     registry:")
    # subject_info(registry) |> display_info()

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
        Process.sleep(10)
        wait_for_clear_message_queue(subject)
    end
  end

  defp wait_demonitor(subject) do
    case subject_info(subject) do
      %{monitors: 0} ->
        :ok

      %{monitors: _monitors} ->
        Process.sleep(10)
        wait_demonitor(subject)
    end
  end
end
