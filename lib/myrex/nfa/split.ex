defmodule Myrex.NFA.Split do
  @moduledoc """
  A process node that broadcasts traversal events to one or more downstream nodes.

  If there is just one downstream process, 
  the node does a direct pass through.
  The total number of messages stays constant.

  If there are multiple downstream processes, 
  the node fans out a copy of the event to all those processes.
  It also notifies the executor process 
  that the number of messages has increased.
  """
  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.NFA.Graph
  alias Myrex.NFA.Proc

  @spec init(T.proc() | T.procs(), String.t()) :: pid()

  def init(procs, label) when is_list(procs) do
    nexts = Enum.map(procs, &Proc.input(&1))
    # fan-out to multiple procs e.g. alternate
    # does not need attach step
    split = Proc.init(__MODULE__, :match, [nexts], label)
    # split procs connections do not use Proc.connect
    # so explicitly add the graph edge here
    Graph.add_edges(split, nexts)
    split
  end

  def init(proc1, label) when is_proc(proc1) do
    # needs attach step for output connection e.g. quantifiers
    pid = Proc.input(proc1)
    split = Proc.init(__MODULE__, :attach, [pid], label)
    # split proc connection does not use Proc.connect
    # so explicitly add the graph edge here
    Graph.add_edge(split, pid)
    split
  end

  @spec attach(pid()) :: no_return()
  def attach(next) when is_pid(next) do
    receive do
      {:attach, proc2} when is_pid(proc2) -> match([next, proc2])
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @spec match([pid()]) :: no_return()
  def match(nexts) when is_list(nexts) do
    receive do
      {_, _, _, _, executor} = msg ->
        delta_n = length(nexts) - 1
        if delta_n > 0, do: add_traversals(executor, delta_n)
        Enum.each(nexts, &Proc.traverse(&1, msg))

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    match(nexts)
  end

  @doc "Notify the executor that the number of traversals has increased."
  @spec add_traversals(pid(), T.count()) :: any()
  def add_traversals(exec, m) when is_pid(exec) and is_count(m), do: send(exec, m)
end
