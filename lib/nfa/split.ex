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

  alias Myrex.NFA.Proc

  @spec init(T.proc() | T.procs()) :: pid()

  def init(procs) when is_list(procs) do
    nexts = Enum.map(procs, &Proc.input(&1))
    # fan-out to multiple procs e.g. alternate
    # does not need attach step
    spawn(__MODULE__, :match, [nexts])
  end

  @spec init(T.proc()) :: pid()
  def init(proc1) when is_proc(proc1) do
    spawn(__MODULE__, :attach, [Proc.input(proc1)])
  end

  @spec attach(T.proc()) :: no_return()
  def attach(next) when is_pid(next) do
    receive do
      proc2 when is_proc(proc2) -> match([next, Proc.input(proc2)])
    end
  end

  @spec match([pid()]) :: no_return()
  def match(nexts) when is_list(nexts) do
    receive do
      {_, _, _, _, executor} = msg ->
        delta_n = length(nexts) - 1
        if delta_n > 0, do: send(executor, delta_n)
        Enum.each(nexts, &send(&1, msg))
    end

    match(nexts)
  end
end
