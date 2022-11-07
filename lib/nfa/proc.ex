defmodule Myrex.NFA.Proc do
  @moduledoc """
  General utilities for networks of processes 
  with a single input process
  and one or more output process
  where downstream processes can be connected.

  The network is built, then the output processes 
  wait for a connection event for the output.
  A connection is made by sending an input address (pid)
  as a message to an output process.

  A network is represented by one of these PID structures:
  * `InOut` shorthand for `{ InOut, InOut }`
  * `{ Input, Output }`
  * `{ Input, [Output] }`
  """

  alias Myrex.Types, as: T

  @doc """
  Connect two process networks.

  Attaches one or more outputs of the first process
  to the downstream input of the second process.

  Returns the second argument.
  """
  @spec connect(T.proc(), T.proc()) :: T.proc()

  def connect(in_out, next) when is_pid(in_out) do
    send(in_out, {:attach, input(next)})
    next
  end

  def connect({_, output}, next) when is_pid(output) do
    send(output, {:attach, input(next)})
    next
  end

  def connect({_, outputs}, next) when is_list(outputs) do
    input = input(next)
    Enum.each(outputs, &send(&1, {:attach, input}))
    next
  end

  @doc "Get the input PID from a process network."
  @spec input(T.proc()) :: pid()
  def input(in_out) when is_pid(in_out), do: in_out
  def input({input, _}) when is_pid(input), do: input

  @doc "Get the output PIDs from a process network."
  @spec output(T.proc()) :: pid() | [pid()]
  def output(in_out) when is_pid(in_out), do: in_out
  def output({_, output}) when is_pid(output), do: output
  def output({_, outputs}) when is_list(outputs), do: outputs

  # gather all the output PIDs from a set of networks
  @spec outputs(T.procs(), [pid()]) :: [pid()]
  def outputs(proc, outputs \\ [])
  def outputs([p | procs], outputs), do: outputs(procs, [output(p) | outputs])
  def outputs([], outputs), do: List.flatten(outputs)

  @doc """
  Continue a traversal by sending new state to the next process.
  """
  @spec traverse(pid(), T.state()) :: :ok
  def traverse(next, state) when is_pid(next) do
    send(next, state)
    :ok
  end
end
