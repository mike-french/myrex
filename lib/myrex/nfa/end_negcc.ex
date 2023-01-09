defmodule Myrex.NFA.EndNegCC do
  @moduledoc """
  The process at the end of negated character class.
  A negated character class uses an AND NOT sequence of peek lookahead.
  """

  alias Myrex.Proc.PNode
  alias Myrex.Proc.Proc
  alias Myrex.Uniset

  @behaviour PNode

  @impl PNode
  def init(nil, label \\ "^]") do
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
      {:parse, <<_c::utf8, rest::binary>>, pos, groups, captures, executor} ->
        # the preceding AND sequence matched on a peek lookahead 
        # now they have all passed, so we advance the input
        Proc.traverse(next, {:parse, rest, pos + 1, groups, captures, executor})

      {:generate, str, uni, gen} ->
        # preceding char match sequence has accumulated negated uniset
        case Uniset.pick_neg(uni) do
          nil -> Proc.traverse(next, {:generate, str, nil, gen})
          char -> Proc.traverse(next, {:generate, <<str::binary, char::utf8>>, nil, gen})
        end

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    run(nil, next)
  end
end
