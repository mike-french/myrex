defmodule Myrex.NFA.Match do
  @moduledoc "Match a single character of input."

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.NFA.Executor
  alias Myrex.NFA.Proc

  @spec init(T.acceptor()) :: pid()
  def init(accept?), do: spawn_link(__MODULE__, :attach, [accept?])

  @spec attach(T.acceptor()) :: no_return()
  def attach(accept?) do
    receive do
      {:attach, next} when is_proc(next) -> match(accept?, Proc.input(next))
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @spec match(T.acceptor(), pid()) :: no_return()
  defp match(accept?, next) do
    receive do
      {<<c::utf8, rest::binary>>, pos, groups, captures, executor} ->
        if accept?.(c) do
          Proc.traverse(next, {rest, pos + 1, groups, captures, executor})
        else
          Executor.notify_result(executor, :no_match)
        end

      {"", _, _, _, executor} ->
        # end of input
        Executor.notify_result(executor, :no_match)

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    match(accept?, next)
  end
end
