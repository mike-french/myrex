defmodule Myrex.NFA.EndAnd do
  @moduledoc """
  The process at the end of an AND match sequence.
  Only a negated character class uses an AND sequence.
  """

  alias Myrex.NFA.Proc

  @spec init() :: pid()
  def init() do
    Proc.init_child(__MODULE__, :attach, [], "[^]")
  end

  @spec attach() :: no_return()
  def attach() do
    receive do
      {:attach, proc} when is_pid(proc) -> match(proc)
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @spec match(pid()) :: no_return()
  defp match(next) do
    receive do
      {<<_c::utf8, rest::binary>>, pos, groups, captures, executor} ->
        # the preceding AND sequence matched on a peek lookahead 
        # now they have all passed, so we advance the input
        Proc.traverse(next, {rest, pos + 1, groups, captures, executor})

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    match(next)
  end
end
