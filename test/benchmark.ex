defmodule Chip.Benchmark do
  @clock :artifacts@clock
  @chip :chip
  @process :gleam@erlang@process

  def run_benchmark() do
    inputs = %{
      "10000 records" => 10000
    }

    Benchee.run(
      %{
        "chip.members (bag) #(group, subject)" => fn {registry, group} ->
          @chip.members(registry, group, 100)
        end
      },
      inputs: inputs,
      before_scenario: fn quantity ->
        {:ok, registry} = @chip.start(:unnamed)
        initialize_registry(registry, quantity)
        registry
      end,
      before_each: fn registry ->
        group = Enum.random([:group_a, :group_b, :group_c])
        {registry, group}
      end,
      after_scenario: fn registry ->
        @chip.stop(registry)
      end,
      time: 5,
      print: %{configuration: false}
    )
  end

  defp initialize_registry(registry, records) do
    for _ <- 1..records do
      group = Enum.random([:group_a, :group_b, :group_c])
      @clock.start(registry, group, 0)
      :ok = wait_for_clear_message_queue(registry)
    end

    nil
  end

  defp wait_for_clear_message_queue(subject) do
    case subject_info(subject) do
      %{message_queue_length: 0} ->
        :ok

      %{message_queue_length: _length, monitors: _monitors} ->
        Process.sleep(10)
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

  def run_benchmark() do
    set = 1..10_000

    IO.puts("\n---------------------------------- THE START ----------------------------------\n")
    size = unit_measurement()
    IO.puts("   Unit of measurement: #{size}")

    {:ok, registry} = @chip.start(:unnamed)

    IO.puts("\n--- Rough memory measurements ---\n")

    IO.puts("   Before registration:")
    subject_info(registry) |> display_info()

    for id <- set do
      group = Enum.random([:group_a, :group_b, :group_c])
      @clock.start(registry, group, 0)

      if Integer.mod(id, 5000) == 0 do
        :ok = wait_for_clear_message_queue(registry)
      end
    end

    IO.puts("   After registration:")
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
        Process.sleep(10)
        wait_for_clear_message_queue(subject)
    end
  end
end
