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

  @spec init(T.proc() | T.procs(), String.t()) :: pid()

  def init(procs, label) when is_list(procs) do
    # fan-out to multiple procs for alternate choice and positive character classes
    # there is no downstream connection for split in addition to the choices
    # so the expected number of attachments is just the number of choices
    split = Proc.init_child(__MODULE__, :attach, [[], length(procs)], label)
    Enum.each(procs, &Proc.connect(split, &1))
    split
  end

  def init(proc1, label) when is_proc(proc1) do
    # every quantifier has a downstream connection 
    # in addition to the quantified process
    # so the expected number of attachments is 1+1
    split = Proc.init_child(__MODULE__, :attach, [[], 2], label)
    Proc.connect(split, proc1)
    split
  end

  @spec attach([pid()], T.count()) :: no_return()
  def attach(nexts, 0), do: match(nexts)

  def attach(nexts, n_attach) when is_list(nexts) and n_attach > 0 do
    receive do
      {:attach, pid} when is_pid(pid) -> attach([pid | nexts], n_attach - 1)
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
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
