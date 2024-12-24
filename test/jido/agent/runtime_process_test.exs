defmodule Jido.Agent.Runtime.ProcessTest do
  use ExUnit.Case, async: true
  require Logger
  import ExUnit.CaptureLog

  alias Jido.Agent.Runtime.Process, as: RuntimeProcess
  alias Jido.Agent.Runtime.State, as: RuntimeState
  alias Jido.Agent.Runtime.Signal, as: RuntimeSignal
  alias JidoTest.TestAgents.SimpleAgent
  alias Jido.Signal

  setup do
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})

    {:ok, supervisor} = start_supervised(DynamicSupervisor)
    agent = SimpleAgent.new("test")

    state = %RuntimeState{
      agent: agent,
      child_supervisor: supervisor,
      pubsub: TestPubSub,
      topic: "test_topic",
      status: :idle,
      pending: :queue.new()
    }

    {:ok, state: state}
  end

  describe "start/2" do
    test "starts a child process and emits signal", %{state: state} do
      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      :ok = Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      assert {:ok, pid} = RuntimeProcess.start(state, child_spec)
      assert Process.alive?(pid)

      process_started = RuntimeSignal.process_started()

      assert_receive %Signal{
        type: ^process_started,
        data: %{child_pid: ^pid, child_spec: ^child_spec}
      }
    end

    test "emits failure signal when start fails", %{state: state} do
      invalid_spec = %{
        id: :invalid_child,
        start: {:not_a_module, :not_a_function, []}
      }

      :ok = Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      capture_log(fn ->
        assert {:error, _reason} = RuntimeProcess.start(state, invalid_spec)
      end)

      process_start_failed = RuntimeSignal.process_start_failed()

      assert_receive %Signal{
        type: ^process_start_failed,
        data: %{child_spec: ^invalid_spec, reason: _reason}
      }
    end
  end

  describe "list/1" do
    test "lists running child processes", %{state: state} do
      # Start a few test processes
      child_spec1 = %{
        id: :test_child1,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      child_spec2 = %{
        id: :test_child2,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      {:ok, pid1} = RuntimeProcess.start(state, child_spec1)
      {:ok, pid2} = RuntimeProcess.start(state, child_spec2)

      children = RuntimeProcess.list(state)
      assert length(children) == 2

      pids = Enum.map(children, fn {:undefined, pid, :worker, _} -> pid end)
      assert pid1 in pids
      assert pid2 in pids
    end

    test "returns empty list when no children", %{state: state} do
      assert [] = RuntimeProcess.list(state)
    end
  end

  describe "terminate/2" do
    test "terminates a specific child process and emits signal", %{state: state} do
      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      {:ok, pid} = RuntimeProcess.start(state, child_spec)
      assert Process.alive?(pid)

      :ok = Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      assert :ok = RuntimeProcess.terminate(state, pid)
      refute Process.alive?(pid)

      process_terminated = RuntimeSignal.process_terminated()

      assert_receive %Signal{
        type: ^process_terminated,
        data: %{child_pid: ^pid}
      }
    end

    test "returns error when terminating non-existent process", %{state: state} do
      non_existent_pid = spawn(fn -> :ok end)
      Process.exit(non_existent_pid, :kill)

      assert {:error, :not_found} = RuntimeProcess.terminate(state, non_existent_pid)
    end
  end

  describe "restart/3" do
    test "restarts a child process and emits signals", %{state: state} do
      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      {:ok, old_pid} = RuntimeProcess.start(state, child_spec)
      assert Process.alive?(old_pid)

      :ok = Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      {:ok, new_pid} = RuntimeProcess.restart(state, old_pid, child_spec)
      assert Process.alive?(new_pid)
      refute Process.alive?(old_pid)
      assert old_pid != new_pid

      # Should receive terminated, started, and restart_succeeded signals
      process_terminated = RuntimeSignal.process_terminated()
      process_started = RuntimeSignal.process_started()
      process_restart_succeeded = RuntimeSignal.process_restart_succeeded()

      assert_receive %Signal{
        type: ^process_terminated,
        data: %{child_pid: ^old_pid}
      }

      assert_receive %Signal{
        type: ^process_started,
        data: %{child_pid: ^new_pid}
      }

      assert_receive %Signal{
        type: ^process_restart_succeeded,
        data: %{old_pid: ^old_pid, new_pid: ^new_pid, child_spec: ^child_spec}
      }
    end

    test "emits failure signal when restart fails", %{state: state} do
      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      {:ok, old_pid} = RuntimeProcess.start(state, child_spec)

      invalid_spec = %{
        id: :invalid_child,
        start: {:not_a_module, :not_a_function, []}
      }

      :ok = Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      capture_log(fn ->
        assert {:error, _reason} = RuntimeProcess.restart(state, old_pid, invalid_spec)
      end)

      process_terminated = RuntimeSignal.process_terminated()
      process_start_failed = RuntimeSignal.process_start_failed()
      process_restart_failed = RuntimeSignal.process_restart_failed()

      assert_receive %Signal{
        type: ^process_terminated,
        data: %{child_pid: ^old_pid}
      }

      assert_receive %Signal{
        type: ^process_start_failed,
        data: %{child_spec: ^invalid_spec}
      }

      assert_receive %Signal{
        type: ^process_restart_failed,
        data: %{child_pid: ^old_pid, child_spec: ^invalid_spec, error: _error}
      }
    end

    test "fails to restart non-existent process", %{state: state} do
      non_existent_pid = spawn(fn -> :ok end)
      Process.exit(non_existent_pid, :kill)

      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      :ok = Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      assert {:error, :not_found} = RuntimeProcess.restart(state, non_existent_pid, child_spec)

      process_restart_failed = RuntimeSignal.process_restart_failed()

      assert_receive %Signal{
        type: ^process_restart_failed,
        data: %{
          child_pid: ^non_existent_pid,
          child_spec: ^child_spec,
          error: {:error, :not_found}
        }
      }
    end
  end
end
