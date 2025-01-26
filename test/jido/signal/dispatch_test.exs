defmodule Jido.Signal.DispatchTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Dispatch

  describe "pid adapter" do
    setup do
      signal = %Jido.Signal{
        id: "test_signal",
        type: "test",
        source: "test",
        time: DateTime.utc_now(),
        data: %{}
      }

      {:ok, signal: signal}
    end

    test "delivers signal asynchronously to pid", %{signal: signal} do
      config = {:pid, [target: self(), delivery_mode: :async]}
      assert :ok = Dispatch.dispatch(signal, config)
      assert_receive {:signal, ^signal}
    end

    test "delivers signal synchronously to pid", %{signal: signal} do
      me = self()

      # Start a process that will respond to sync messages
      pid =
        spawn(fn ->
          receive do
            {:"$gen_call", from, {:signal, signal}} ->
              GenServer.reply(from, :ok)
              send(me, {:received, signal})
          end
        end)

      config = {:pid, [target: pid, delivery_mode: :sync]}
      assert :ok = Dispatch.dispatch(signal, config)
      assert_receive {:received, ^signal}
    end

    test "returns error when target process is not alive", %{signal: signal} do
      pid = spawn(fn -> :ok end)
      # Ensure process is dead
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}

      config = {:pid, [target: pid, delivery_mode: :async]}
      assert {:error, :process_not_alive} = Dispatch.dispatch(signal, config)
    end
  end

  describe "named adapter" do
    setup do
      signal = %Jido.Signal{
        id: "test_signal",
        type: "test",
        source: "test",
        time: DateTime.utc_now(),
        data: %{}
      }

      {:ok, signal: signal}
    end

    test "delivers signal asynchronously to named process", %{signal: signal} do
      name = :test_named_process
      Process.register(self(), name)

      config = {:named, [target: {:name, name}, delivery_mode: :async]}
      assert :ok = Dispatch.dispatch(signal, config)
      assert_receive {:signal, ^signal}
    end

    test "returns error when named process not found", %{signal: signal} do
      config = {:named, [target: {:name, :nonexistent_process}, delivery_mode: :async]}
      assert {:error, :process_not_found} = Dispatch.dispatch(signal, config)
    end
  end

  describe "bus adapter" do
    setup do
      signal = %Jido.Signal{
        id: "test_signal",
        type: "test",
        source: "test",
        time: DateTime.utc_now(),
        data: %{}
      }

      bus_name = :"test_bus_#{:erlang.unique_integer()}"
      start_supervised!({Jido.Bus, name: bus_name})

      {:ok, signal: signal, bus_name: bus_name}
    end

    test "delivers signal to bus", %{signal: signal, bus_name: bus_name} do
      config = {:bus, [target: bus_name, stream: "test_stream"]}
      assert :ok = Dispatch.dispatch(signal, config)
    end

    test "returns error when bus not found", %{signal: signal} do
      config = {:bus, [target: :nonexistent_bus, stream: "test_stream"]}
      assert {:error, :bus_not_found} = Dispatch.dispatch(signal, config)
    end
  end

  describe "validate_opts/1" do
    test "validates pid adapter configuration" do
      config = {:pid, [target: self(), delivery_mode: :async]}
      assert {:ok, {adapter, opts}} = Dispatch.validate_opts(config)
      assert adapter == :pid
      assert Keyword.get(opts, :target) == self()
      assert Keyword.get(opts, :delivery_mode) == :async
    end

    test "validates bus adapter configuration" do
      config = {:bus, [target: :test_bus, stream: "test_stream"]}
      assert {:ok, {adapter, opts}} = Dispatch.validate_opts(config)
      assert adapter == :bus
      assert Keyword.get(opts, :target) == :test_bus
      assert Keyword.get(opts, :stream) == "test_stream"
    end

    test "validates named adapter configuration" do
      config = {:named, [target: {:name, :test_process}, delivery_mode: :async]}
      assert {:ok, {adapter, opts}} = Dispatch.validate_opts(config)
      assert adapter == :named
      assert Keyword.get(opts, :target) == {:name, :test_process}
      assert Keyword.get(opts, :delivery_mode) == :async
    end

    test "returns error for invalid adapter" do
      config = {:invalid_adapter, []}
      assert {:error, _} = Dispatch.validate_opts(config)
    end
  end
end
