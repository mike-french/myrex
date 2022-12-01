defmodule Myrex.NFA.EndAnd do
  @moduledoc """
  The process at the end of an AND match sequence.
  Only a negated character class uses an AND sequence.
  """

  alias Myrex.Proc.PNode
  alias Myrex.Proc.Proc

  @behaviour PNode

  @impl PNode
  def init(nil, label \\ "[^]") do
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
      {<<_c::utf8, rest::binary>>, pos, groups, captures, executor} ->
        # the preceding AND sequence matched on a peek lookahead 
        # now they have all passed, so we advance the input
        Proc.traverse(next, {rest, pos + 1, groups, captures, executor})

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    run(nil, next)
  end
end
