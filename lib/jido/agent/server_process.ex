defmodule Jido.Agent.Server.Process do
  @moduledoc false

  use ExDbug, enabled: false
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.Output, as: ServerOutput

  @typedoc "Child process specification"
  @type child_spec :: Supervisor.child_spec() | {module(), term()} | module()

  @typedoc "Child process ID"
  @type child_pid :: pid()

  @typedoc "Child process start result"
  @type start_result :: {:ok, child_pid() | [child_pid()]} | {:error, term()}

  @typedoc "Server state type"
  @type server_state :: ServerState.t()

  @doc """
  Starts the DynamicSupervisor for managing an Agent's child processes.

  The supervisor uses a :one_for_one strategy, meaning each child is supervised
  independently.

  ## Parameters
  - state: Current server state

  ## Returns
  - `{:ok, updated_state}` - Supervisor started successfully
  - `{:error, reason}` - Failed to start supervisor
  """
  @spec start_supervisor(server_state()) :: {:ok, server_state()} | {:error, term()}
  def start_supervisor(%ServerState{} = state) do
    dbug("Starting supervisor", state: state)

    case DynamicSupervisor.start_link(strategy: :one_for_one) do
      {:ok, supervisor} ->
        dbug("Supervisor started successfully", supervisor: supervisor)
        {:ok, %{state | child_supervisor: supervisor}}

      {:error, _reason} = error ->
        dbug("Failed to start supervisor", error: error)
        error
    end
  end

  @doc """
  Stops the DynamicSupervisor and all its child processes.

  ## Parameters
  - state: Current server state

  ## Returns
  - `:ok` - Supervisor stopped successfully
  - `{:error, reason}` - Failed to stop supervisor
  """
  @spec stop_supervisor(server_state()) :: :ok | {:error, term()}
  def stop_supervisor(%ServerState{child_supervisor: supervisor})
      when is_pid(supervisor) do
    dbug("Stopping supervisor", supervisor: supervisor)

    try do
      DynamicSupervisor.stop(supervisor, :shutdown)
    catch
      :exit, _reason ->
        dbug("Supervisor already stopped", reason: _reason)
        :ok
    end
  end

  def stop_supervisor(%ServerState{} = _state) do
    dbug("No supervisor to stop")
    :ok
  end

  @doc """
  Starts one or more child processes under the Server's DynamicSupervisor.

  Can accept either a single child specification or a list of specifications.
  For lists, all processes must start successfully or none will be started.

  ## Parameters
  - state: Current server state
  - child_specs: Child specification(s) to start

  ## Returns
  - `{:ok, state, pid}` - Single child started successfully
  - `{:ok, state, [pid]}` - Multiple children started successfully
  - `{:error, reason}` - Failed to start child(ren)

  ## Examples

      # Start a single child
      {:ok, state, pid} = Process.start(state, child_spec)

      # Start multiple children
      {:ok, state, pids} = Process.start(state, [spec1, spec2, spec3])
  """
  @spec start(server_state(), child_spec() | [child_spec()]) ::
          {:ok, server_state(), child_pid() | [child_pid()]} | {:error, term()}
  def start(%ServerState{child_supervisor: supervisor} = state, child_specs)
      when is_pid(supervisor) and is_list(child_specs) do
    dbug("Starting multiple child processes", state: state, specs: child_specs)
    results = Enum.map(child_specs, &start_child(state, &1))

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {successes, []} ->
        pids = Enum.map(successes, fn {:ok, pid} -> pid end)
        dbug("Successfully started all children", pids: pids)
        {:ok, state, pids}

      {_, failures} ->
        reasons = Enum.map(failures, fn {:error, reason} -> reason end)
        dbug("Failed to start some children", failures: reasons)
        {:error, reasons}
    end
  end

  def start(%ServerState{} = state, child_spec) do
    dbug("Starting single child process", state: state, spec: child_spec)

    case start_child(state, child_spec) do
      {:ok, pid} ->
        dbug("Successfully started child", pid: pid)
        {:ok, state, pid}

      error ->
        dbug("Failed to start child", error: error)
        error
    end
  end

  @doc """
  Lists all child processes currently running under the Server's DynamicSupervisor.

  Returns a list of child specifications in the format:
  `{:undefined, pid, :worker, [module]}`

  ## Parameters
  - state: Current server state

  ## Returns
  List of child specifications
  """
  @spec list(server_state()) :: [{:undefined, pid(), :worker, [module()]}]
  def list(%ServerState{child_supervisor: supervisor}) when is_pid(supervisor) do
    dbug("Listing child processes", supervisor: supervisor)
    children = DynamicSupervisor.which_children(supervisor)
    dbug("Found children", children: children)
    children
  end

  @doc """
  Terminates a specific child process under the Server's DynamicSupervisor.

  Emits process termination events on success/failure.

  ## Parameters
  - state: Current server state
  - child_pid: PID of child process to terminate

  ## Returns
  - `:ok` - Process terminated successfully
  - `{:error, :not_found}` - Process not found
  """
  @spec terminate(server_state(), child_pid()) :: :ok | {:error, :not_found}
  def terminate(%ServerState{child_supervisor: supervisor} = state, child_pid)
      when is_pid(supervisor) do
    dbug("Terminating child process", state: state, child_pid: child_pid)

    case DynamicSupervisor.terminate_child(supervisor, child_pid) do
      :ok ->
        dbug("Child process terminated successfully")

        :process_terminated
        |> ServerSignal.event_signal(state, %{child_pid: child_pid})
        |> ServerOutput.emit()

        :ok

      {:error, _reason} = error ->
        dbug("Failed to terminate child process", error: error)
        error
    end
  end

  @doc """
  Restarts a specific child process under the Server's DynamicSupervisor.

  This performs a full stop/start cycle:
  1. Terminates the existing process
  2. Starts a new process with the same specification
  3. Emits appropriate lifecycle events

  ## Parameters
  - state: Current server state
  - child_pid: PID of process to restart
  - child_spec: Specification to use for new process

  ## Returns
  - `{:ok, new_pid}` - Process restarted successfully
  - `{:error, reason}` - Failed to restart process
  """
  @spec restart(server_state(), child_pid(), child_spec()) :: {:ok, pid()} | {:error, term()}
  def restart(%ServerState{} = state, child_pid, child_spec) do
    dbug("Restarting child process", state: state, child_pid: child_pid, spec: child_spec)

    with :ok <- terminate(state, child_pid),
         {:ok, _new_pid} = result <- start(state, child_spec) do
      dbug("Successfully restarted child process", result: result)

      :process_restarted
      |> ServerSignal.event_signal(state, %{child_pid: child_pid, child_spec: child_spec})
      |> ServerOutput.emit()

      result
    else
      error ->
        dbug("Failed to restart child process", error: error)

        :process_failed
        |> ServerSignal.event_signal(state, %{
          child_pid: child_pid,
          child_spec: child_spec,
          error: error
        })
        |> ServerOutput.emit()

        error
    end
  end

  # Private Functions

  @spec start_child(server_state(), child_spec()) :: {:ok, pid()} | {:error, term()}
  defp start_child(%ServerState{} = _state, []) do
    dbug("Empty child spec provided, skipping process start")
    {:ok, nil}
  end

  defp start_child(%ServerState{child_supervisor: supervisor} = state, child_spec) do
    dbug("Starting child process", supervisor: supervisor, spec: child_spec)

    require Logger
    Logger.debug("Starting child process #{inspect(child_spec)}")

    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, pid} = result ->
        dbug("Child process started successfully", pid: pid)

        :process_started
        |> ServerSignal.event_signal(state, %{child_pid: pid, child_spec: child_spec})
        |> ServerOutput.emit()

        result

      {:error, reason} = error ->
        dbug("Failed to start child process", reason: reason)

        :process_failed
        |> ServerSignal.event_signal(state, %{child_spec: child_spec, error: reason})
        |> ServerOutput.emit()

        error
    end
  end
end
