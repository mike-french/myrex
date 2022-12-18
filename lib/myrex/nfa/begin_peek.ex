defmodule Myrex.NFA.BeginPeek do
  @moduledoc """
  The process at the start of an AND NOT peek lookahead sequence.
  Only a negated character class uses a peek sequence.
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.Proc.PNode
  alias Myrex.Proc.Proc

  @behaviour PNode

  @impl PNode
  def init(nil, label \\ "[^") do
    Proc.init_child(__MODULE__, :attach, [nil], label)
  end

  @impl PNode
  def attach(nil) do
    receive do
      {:attach, proc} when is_pid(proc) -> run(nil, proc)
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @impl PNode
  def run(nil, next) do
    receive do
      state when T.is_state(state) ->
        # beginning a peek sequence is a no-op for parsing
        Proc.traverse(next, state)

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    run(nil, next)
  end
end