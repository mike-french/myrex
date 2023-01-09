defmodule Myrex.NFA.BeginNegCC do
  @moduledoc """
  The process at the start of negated character class.
  A negated character class uses an AND NOT sequence of peek lookahead.
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.Proc.PNode
  alias Myrex.Proc.Proc
  alias Myrex.Uniset

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
      state when T.is_par_state(state) ->
        # beginning a peek sequence is a no-op for parsing
        Proc.traverse(next, state)

      {:generate, str, nil, gen} ->
        # put an empty Uniset in the gen state to start NegCC accumulation
        Proc.traverse(next, {:generate, str, Uniset.new(:none), gen})

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    run(nil, next)
  end
end
