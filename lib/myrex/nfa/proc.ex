defmodule Myrex.NFA.Proc do
  @moduledoc """
  General utilities for networks of processes 
  with a single input process
  and one or more output processes.

  The network is built, then the output processes 
  wait for a connection event from a downstream process.
  A connection is made by sending an input address (PID)
  in an `attach` message to the output processes.

  A network is represented by one of these PID structures:
  * `InOut` shorthand for `{ InOut, InOut }`
  * `{ Input, Output }`
  * `{ Input, [Output] }`
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.NFA.Graph

  @doc """
  Connect two process networks.

  Attaches one or more outputs of the first process
  to the downstream input of the second process.

  Returns the second argument.
  """
  @spec connect(T.proc(), T.proc()) :: T.proc()

  def connect(in_out, next) when is_pid(in_out) and is_proc(next) do
    dst = input(next)
    Graph.add_edge(in_out, dst)
    send(in_out, {:attach, dst})
    next
  end

  def connect({_, output}, next) when is_pid(output) and is_proc(next) do
    connect(output, next)
  end

  def connect({_, outputs}, next) when is_list(outputs) and is_proc(next) do
    dst = input(next)
    Enum.each(outputs, &connect(&1, dst))
    next
  end

  @doc """
  Connect the output of the current process to a downstream process.

  Use an embedded receive for attachment, 
  rather than an existing receive clause in the current process.

  Returns the argument.
  """
  @spec connect_to(pid()) :: pid()
  def connect_to(next) when is_pid(next) do
    connect(self(), next)

    receive do
      {:attach, ^next} -> :ok
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    next
  end

  @doc "Get the input PID from a process network."
  @spec input(T.proc()) :: pid()
  def input(in_out) when is_pid(in_out), do: in_out
  def input({input, _}) when is_pid(input), do: input

  @doc "Get the input PIDs from a set of process networks."
  @spec inputs(T.procs()) :: [pid()]
  def inputs(procs) when is_list(procs), do: Enum.map(procs, &input/1)

  @doc "Get the output PIDs from a process network."
  @spec output(T.proc()) :: pid() | [pid()]
  def output(in_out) when is_pid(in_out), do: in_out
  def output({_, output}) when is_pid(output), do: output
  def output({_, outputs}) when is_list(outputs), do: outputs

  # gather all the output PIDs from a set of process networks
  @spec outputs(T.proc() | T.procs()) :: [pid()]
  def outputs(proc) when is_proc(proc), do: List.wrap(output(proc))
  def outputs(procs) when is_list(procs), do: procs |> Enum.map(&output/1) |> List.flatten()

  @doc """
  Continue a traversal by sending a new state to the next process.
  """
  @spec traverse(T.pid(), T.state()) :: :ok
  def traverse(next, state) when is_pid(next) do
    send(next, state)
    :ok
  end

  @doc """
  Spawn a linked child NFA process.
  Register the named node in the graph
  managed by the calling process 
  (not the spawned process).
  """
  @spec init_child(module(), atom(), list(), String.t()) :: pid()
  def init_child(m, f, a, name) do
    spawn_link(m, f, a) |> Graph.add_node(name)
  end

  @doc """
  Spawn the parent NFA process.
  Register the named node in the graph
  managed by the spawned process
  (not the calling process)
  """
  @spec init_parent(module(), atom(), list(), String.t(), boolean()) :: pid()
  def init_parent(m, f, a, name, enable? \\ false)

  def init_parent(m, f, a, _name, false) do
    spawn_link(m, f, a)
  end

  def init_parent(m, f, a, name, true) do
    # bootstrap the graph from a spawned local function
    # then execute the NFA graph parent process
    spawn_link(__MODULE__, :parent, [m, f, a, name])
  end

  def parent(m, f, a, name) do
    # activate the graph in the spawned process
    Graph.enable()
    Graph.add_node(self(), name)
    apply(m, f, a)
  end
end
