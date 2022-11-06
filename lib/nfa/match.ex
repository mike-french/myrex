defmodule Myrex.NFA.Match do
  @moduledoc "Match a single character of input."

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.NFA.Proc

  @spec init(T.acceptor()) :: pid()
  def init(accept?), do: spawn(__MODULE__, :attach, [accept?])

  @spec attach(T.acceptor()) :: no_return()
  def attach(accept?) do
    receive do
      next when is_proc(next) -> match(accept?, Proc.input(next))
    end
  end

  @spec match(T.acceptor(), pid()) :: no_return()
  defp match(accept?, next) do
    receive do
      {<<c::utf8, rest::binary>>, pos, groups, captures, executor} = foo ->
        if accept?.(c) do
          send(next, {rest, pos + 1, groups, captures, executor})
        else
          send(executor, :no_match)
        end

      {"", _, _, _, executor} ->
        # end of input
        send(executor, :no_match)
    end

    match(accept?, next)
  end
end
